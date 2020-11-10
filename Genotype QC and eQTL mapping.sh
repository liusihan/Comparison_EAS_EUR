##Sample match check (QTLtools and NGSmakecheck)
ls RNA-seq/BAM/*Aligned.sortedByCoord.out_Pit_re_marked.bam | awk '{split($1,a,"/");split(a[5],b,".");print b[1]}' | while read line; do QTLtools_1.0_CentOS6.8_x86_64 match --bam RNA-seq/BAM/"$line".sortedByCoord.out_Pit_re_marked.bam --vcf DNA-seq/VCF/Combine/chr22.vcf.gz --filter-mapping-quality 150 --out "$line"; cat "$line" | awk '{print $1"""_"""substr("'$line'",1,length("'$line'")-7),$7/$3,$8/$4}'>"$line".reslut;done

##Sex check
# remove X chromosome pseudo-autosomal region
plink --bfile chrall --split-x hg19 --make-bed --out chrall.splitX

#sexcheck (use default 0.2/0.8 F-statistic thresholds, eyeballing the distribution of F-estimates)
plink --bfile chrall.splitX --check-sex ycount 0.2 0.8 --out chrall.sexcheck

##Population structure check
plink --bfile chrall --bmerge KG.bim KG.bed KG.fam --make-bed --out population_structure_check
plink --bfile population_structure_check --pca 20 --out population_structure_check

##PI_HAT check
plink --bfile chrall.splitX --genome --out chrall

##Remove Sex miss match sample
for i in {1..22} X
do
vcftools --gzvcf raw_chr"$i".vcf.gz --remove Sex_miss.ID --recode --out chr"$i"_fsample
done


##refine genotype and remove SNPs with R2<0.3
for i in {1..22}
do
java -jar beagle.27Jul16.86a.jar map=plink.chr"$i".GRCh37.map gl=chr"$i"_fsample.recode.vcf out=chr$i.refine.gl
zcat chr$i.refine.gl.vcf.gz | awk '{if($1~/^#/){print}else{flag=0;split($8,a,";");for(i in a){if(a[i]~/^AR2=/&&substr(a[i],5)>=0.3){flag=1}}if(flag==1){print}}}'>chr$i.beagle.refine.r2.vcf
done


##Combine all chr
cat chr22.beagle.refine.r2.vcf |head -n 11 >all.refine.r2.vcf
for i in {1..22} 
do
cat chr"$i".beagle.refine.r2.vcf | awk 'NR>=12' >>all.refine.r2.vcf
done


##Pre-imputation preparation script(HRC:HRC-1000G-check-bim.pl)
vcftools --vcf all.refine.r2.vcf --plink --out all.refine
plink --vcf all.refine.r2.vcf --out all.refine --make-bed
plink --bfile all.refine --out all.refine --freq
perl HRC-1000G-check-bim.pl -b all.refine.bim -f all.refine.frq -r 1000GP_Phase3_combined.legend.gz --1000g --pop EAS -t 0.1

##plink to vcf
bash Run-plink.sh(#The perl script will generate a list of PLINK commands to be run on the original dataset)
for CHR in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do plink --bfile all.refine-updated-chr${CHR} --out ${CHR} --recode vcf-fid
bgzip -c ${CHR}.vcf >${CHR}.vcf.gz done


###Imputation (Michigan imputation serve: https://imputationserver.sph.umich.edu/index.html)

#wget download the result and Unzip the VCF files using the password provided in the email:
ls *.zip | xargs -I {} unzip -P 'myPassword' {}
e.g.: ls *.zip | xargs -I {} unzip -P 'dEIi2b7OQSd@Ia' {}

#Remove snps which R2<0.3
for i in {1..22}
do 
zcat chr$i.dose.vcf.gz | awk '{if($1~/^#/){print}else{flag=0;flag2=0;split($8,a,";");for(i in a){if((a[i]~/^R2=/&&substr(a[i],4)>=0.3)){flag=1};if(a[i]~/^MAF=/&&substr(a[i],5)>=0.01){flag2=1}}if(flag==1&&flag2==1){print}}}'>chr$i.michigan.impute.r2.maf.vcf 
done


#Remove snps with AF diff >0.1 and hwe<0.000001 maf<0.05
cat chr10.michigan.impute.r2.maf.vcf | head -n 14 >all.michigan.impute.r2.maf.vcf
for i in {1..22}
do
cat chr"$i".michigan.impute.r2.maf.vcf | awk 'NR>=15' >>all.michigan.impute.r2.maf.vcf 
done


vcftools --vcf all.michigan.impute.r2.maf.vcf --plink --out all.impute
plink --file all.impute --out all.impute --make-bed
plink --bfile all.impute --out all.impute --freq
perl HRC-1000G-check-bim.pl -b all.impute.bim -f all.impute.frq -r /zs32/data-analysis/liucy_group/shareData/Chinese_brain/1000GP_Phase3_combined.legend.gz --1000g --pop EAS -t 0.1

bash Run-plink.sh(#The perl script will generate a list of PLINK commands to be run on the original dataset)

for i in {1..22}
do plink --bfile all.impute-updated-chr"$i" --hwe 0.000001 --maf 0.05 --make-bed --out all.impute-updated-chr"$i"_filter
done

for CHR in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do plink --bfile all.impute-updated-chr${CHR}_filter --out ${CHR} --recode vcf-fid; done

#generate file contain allele frequncy to assece imputation accuracy
for i in {1..22}; do cat chr"$i".michigan.impute.r2.maf.vcf | awk 'NR==FNR&&$1!~/#/{split($8,a,";");for(i in a){if(a[i]~/^AF=/){b[$3""":"""$4""":"""$5]=substr(a[i],4)}}}NR>FNR{split($1,a,":");if("'$i'"""":"""a[2]""":"""a[3]""":"""a[4] in b){print $1,b["'$i'"""":"""a[2]""":"""a[3]""":"""a[4]],$8};if("'$i'"""":"""a[2]""":"""a[4]""":"""a[3] in b){print $1,b["'$i'"""":"""a[2]""":"""a[4]""":"""a[3]],1-$8}}'  - <(zcat 1000GP_Phase3_chr"$i".legend.gz) >>Freq_compare_1000G.txt; done

#make genotype files for QTL maaping
for i in {1..22}; do     awk '          
        BEGIN{FS="\t";OFS="\t"}
        NR==FNR{for(i=2;i<=NF;i++) order[$i]=i+8}
        NR>FNR{
            if($1~/^##/){
                print $0
            }else if($1=="#CHROM"){
                for(i=10;i<=NF;i++){
                    if($i in order){
                        ind[order[$i]]=i
                    }
                }
                printf($1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8"\t"$9)
                for(i=10;i<=length(ind)+9;i++){
                    n=ind[i]
                    printf("\t"$n)
                }
                printf("\n")
            }else{
                if($5~/,/) next
                $3=$1"_"$2"_"$4"_"$5;
                printf($1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8"\t"$9)
                for(i=10;i<=length(ind)+9;i++){
                    n=ind[i]
                    printf("\t"$n)
                }
                printf("\n")
            }
        }
    ' <(zcat phenotype.chr10.bed.gz  | awk 'NR==1{for(i=5;i<=NF;i++){b=b"""\t"""$i};print b}') <(cat "$i".vcf) | bgzip>genotypes.all.chr$i.vcf.gz; tabix -p vcf genotypes.all.chr$i.vcf.gz; done

## Make phenotype bed file
# Convert to bed & locate TSS for reverse strand
awk 'BEGIN{FS="\t";OFS="\t"}NR==FNR{a[$1]=1}NR>FNR{if($4 in a){start=$3;$3=$2;$2=start}; print $0}' <(zcat gencode.v19.annotation.bed.gz |awk 'BEGIN{FS="[\t.]"}$5=="gene"{a[$7]=$6}END{for(i in a){if(a[i]=="-") print i}}') <(awk 'BEGIN{FS="\t";OFS="\t"}NR==FNR&&$5=="gene"{split($8,s,".");a[s[1]]=$1"\t"$2"\t"$3}NR>FNR&&FNR==1{print "#chr\tstart\tend\tgene"$0}NR>FNR&&FNR>1&&($1 in a){print a[$1],$0}' <(zcat gencode.v19.annotation.bed.gz) log2cpm.fgene.fsample.qn) |sed -e's/^chr//'>log2cpm.fgene.fsample.qn.bed

# Split by chr
for i in {1..22} X
do
cat log2cpm.fgene.fsample.qn.bed | awk 'NR==1{print $0}NR>=2&&$1=="'$i'"{print $0}' | sort -k1,1n -k2,2n | awk '{ $4=$4" . +"; print $0 }' | tr " " "\t" | bgzip >phenotype.chr"$i".bed.gz
tabix -p bed phenotype.chr$i.bed.gz
done


## Map eQTL
#nominal
parallel -j 10 QTLtools_1.0_CentOS6.8_x86_64 cis --vcf genotypes.all.chr{}.vcf.gz --bed phenotype.chr{}.bed.gz --region {} --cov Covariant.txt --out eqtl.nopermute.chr{} --nominal 1 ::: {1..22} X

#permutation test
parallel -j 10 QTLtools_1.0_CentOS6.8_x86_64 cis --vcf genotypes.all.chr{}.vcf.gz --bed phenotype.chr{}.bed.gz --region {} --cov Covariant.txt --out eqtl.permute.chr{} --permute 1000 ::: {1..22} X
