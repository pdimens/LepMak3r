from os import path
import glob
#FILENAMES = [os.path.basename(i) for i in glob.iglob("test/*.R1.fq.gz")]
#FILEBASENAMES = [i.replace('.R1.fq.gz', '') for i in FILENAMES]

#initial VCF file
vcf_file = [os.path.basename(i) for i in glob.glob("./*.vcf")]

# SeperateChromosomes2 params
lod_min = 20
lod_max = 40
lod_range = list(range(lod_min, lod_max+1))
exp_lg = 24
lg_range = list(range(1, exp_lg+1))
ITER = list(range(1,100+1))

rule all:
    input:
        "ordermarkers/best.trim/trim.log"
        #"reorder.done"
        #"trim.done"

rule parentcall:
    input:
        vcf = expand("{vcffile}", vcffile = vcf_file),
        pedigree = "pedigree.txt"
    output:
        "data.call.gz"
    message:
        """
        Creating Lep-Map3 data file from VCF and pedigree files
        """
    shell:
        "java -cp LM3 ParentCall2 data={input.pedigree} vcfFile={input.vcf} removeNonInformative=1 | gzip > data.call.gz"

rule filtering:
    input:
        "data.call.gz"
    output:
        "data_f.call.gz"
    message:
        """
        Filtering the data
        """
    shell:
        """
        echo -e -n '\nSpecify your data tolerance (0.0001 to 0.01):  '
        read -r
        zcat {input} | java -cp LM3 Filtering2 data=- dataTolerance=$REPLY | gzip > data_f.call.gz
        """

rule separatechromosomes:
    input:
        "data_f.call.gz"
    output:
        map = "maps.splitchrom/map.{lod_range}"
    message:
        """
        Creating maps for specified LOD range >> maps.splitchrom/map.LG
        """
    threads: 8
    params:
        lod_lim = "lodLimit={lod_range}",
        dist_lod = "distortionLod=1"
    shell:
        "zcat {input} | java -cp LM3 SeparateChromosomes2 data=- {params.lod_lim} {params.dist_lod} numThreads={threads} > {output}" 

rule mapsummary:
    input:
        expand("maps.splitchrom/map.{LOD}", LOD = lod_range)
    output:
        "maps.splitchrom/maps.summary.txt"
    message:
        """
        Combining map summaries >> maps.splitchrom/maps.summary.txt
        """
    shell:
        "scripts/map_summary.sh {lod_max}"

rule joinsingles:
    input:
        datacall = "data_f.call.gz",
        map_summ = "maps.splitchrom/maps.summary.txt"
    output:
        "map.master"
    threads: 8
    params:
        lod_limit = "lodLimit=10",
        lod_diff = "lodDifference=2",
        iterate = "iterate=1",
    shell:
        """
        echo -n -e '\nWhich map would you like to use (e.g. map.15)? map.'
        read -r
        zcat {input.datacall} | java -cp LM3 JoinSingles2All map=maps.splitchrom/map.$REPLY data=- {params.lod_limit} {params.lod_diff} {params.iterate} numThreads={threads} > {output}
        echo 'Your filtered map can be found in the working directory'
        """

rule ordermarkers:
    input:
        datacall = "data_f.call.gz",
        filt_map = "map.master"
    output:
        "ordermarkers/ordered.{lg_range}.{ITER}"
    log:
        "ordermarkers/logs/ordered.{lg_range}.{ITER}.log"
    message:
        """
        Ordering the markers on linkage groups 1:N
        This may take a while depending on the number of provided threads and requested iterations
        """
    params:
        dist_method = "useKosambi=1",
        chrom = "{lg_range}"
    threads: 2
    shell:
        """
        zcat {input.datacall} | java -cp LM3 OrderMarkers2 map={input.filt_map} data=- numThreads={threads} {params.dist_method} chromosome={params.chrom} &> {log}
        grep -A 100000 \*\*\*\ LG\ \= {log} > {output}
        """
        
rule summarize_likelihoods:
    input:
        expand("ordermarkers/ordered.{LG}.{ITER}", LG = lg_range, ITER = ITER)
    output:
        "ordermarkers/likelihoods.txt"
    message:
        """
        Summarizing + sorting likelihoods from each iteration >> ordermarkers/likelihoods.txt
        """
    shell:
        """
        for LIKE in {input}; do 
            LG=$(echo $(basename $LIKE) | cut -d "." -f1,2)
            ITERUN=$(echo $LIKE | cut -d "." -f3)
            LIKELIHOOD=$(cat $LIKE | grep "likelihood = " | cut -d " " -f7)
            echo -e "$LG\t$ITERUN\t$LIKELIHOOD" >> {output}.tmp
        done
        sort {output}.tmp -k1,1V -k3,3nr > {output} && rm {output}.tmp
        """

rule find_bestlikelihoods:
    input:
        "ordermarkers/likelihoods.txt"
    output:
        "ordermarkers/bestlikelihoods.txt"
    message:
        """
        Identifying ordered maps with best likelihoods for each LG >> ordermarkers/bestlikelihoods.txt
        """
    shell:
        """
        LG=$(find ordermarkers -maxdepth 1 -name "ordered.*.*" | cut -d "." -f2 | sort -V | uniq)
        NUMITER=$(find ordermarkers -maxdepth 1 -name "ordered.*.*" | cut -d "." -f3 | sort -V | uniq | tail -1)
        TOTALMAPS=$(find ordermarkers -maxdepth 1 -name "ordered.*.*" | wc -l) 
        for i in $(seq 1 $NUMITER $TOTALMAPS); do
            LIKELYMAP=$(sed -n ${{i}}p ordermarkers/likelihoods.txt | cut -f1,2 | awk '{{print $0, $1 "." $NF}}' | cut -d ' ' -f2)
            echo "ordermarkers/$LIKELYMAP" >> ordermarkers/bestlikelihoods.txt
        done
        """

#rule isolate_best:
#    input:
#        "ordermarkers/bestlikelihoods.txt"
#    output:
#        "ordermarkers/best/ordered.{lg_range}"
#    message:
#        """
#        Creating softlinks to iterations with highest likelihoods >> ordermarkers/best/ordered.LG
#        """
#    params:
#        grep_lg = "ordermarkers/ordered.{lg_range}."
#
#    shell:
#        """
#        BEST=$(grep -F {params.grep_lg} {input})
#        ln -sr $BEST {output}
#        """

rule trim_edges_clusters:
    input:
        "ordermarkers/bestlikelihoods.txt"
    output:
        "ordermarkers/best.trim/ordered.{lg_range}.trimmed"
    log:
        "ordermarkers/best.trim/ordered.{lg_range}.removed",
        "ordermarkers/best.trim/ordered.{lg_range}.trim.pdf"
    params:
        grep_lg = "ordermarkers/ordered.{lg_range}.",
        trim_threshold = "10",
    message:
        """
        Scanning the first and last 15% of markers in {input} and removing clusters >{params.trim_threshold}cM apart from the other markers. 
        """
    shell:
        """
        LG=$(grep -F {params.grep_lg} {input})
        Rscript scripts/LepMapp3rQA_single.r $(pwd) $LG {params.trim_threshold}
        """


#rule trimming:
#    input:
#        "ordermarkers/best/{orderfile}"
#    output:
#        "ordermarkers/best.trim/{orderfile}.trimmed"
#    log:
#        "ordermarkers/best.trim/{orderfile}.removed",
#        "ordermarkers/best.trim/{orderfile}.trim.pdf"
#    params:
#        trim_threshold = "10",
#    message:
#        """
#        Scanning the first and last 15% of markers in {input} and removing clusters >{params.trim_threshold}cM apart from the other markers. 
#        """
#    shell:
#        """
#        Rscript scripts/LepMapp3rQA_single.r $(pwd) {input} {params.trim_threshold}
#        """

rule trim_summary:
    input:
        expand("ordermarkers/best.trim/ordered.{lg}.trimmed", lg = lg_range)
    output:
        "ordermarkers/best.trim/trim.log"
    message:
        "Summarizing trim logs into single trim.log file"
    shell:
        """
        echo -e "LG\trm_marker" >> {output}
        for each in ordermarkers/best.trim/ordered.*.removed ; do
            BASE=$(basename $each | cut -d "." -f1,2)
            sed -e "s/^/$BASE /" $each >> {output}.tmp 
        done
        sort -V {output}.tmp > {output} && rm {output}.tmp 
        """

#rule trimcheck:
#   input:
#       "ordermarkers/best.trim/trim.log",
#       expand("ordermarkers/best.trim/ordered.{lg}.trimmed", lg = lg_range)
#       #expand("ordermarkers/best.trim/ordered.{lg}.{iter}.trimmed", lg = lg_range, iter = ITER, allow_missing = True)
#   output:
#       "trim.done"
#   shell:
#       "touch {output}"

rule reorder:
    input:
        datacall = "data_f.call.gz",
        filt_map = "map.master",
        trimlog = "ordermarkers/best.trim/trim.log",
        lg_order = "ordermarkers/best.trim/{trimfile}.trimmed"
    output:
        "reordermarkers/{trimfile}.{ITER}"
    log:
        "reordermarkers/logs/{trimfile}.{ITER}.log"
    message:
        """
        Reordering the markers for each linkage group using the trimmed orders with the best likelihoods from initial ordering.
        This may take a while depending on the number of provided threads and requested iterations
        """
    params:
        dist_method = "useKosambi=1",
        eval_order="evaluateOrder=ordermarkers/best.trim/{trimfile}.trimmed"
    threads: 2
    shell:
        """
        zcat {input.datacall} | java -cp LM3 OrderMarkers2 map={input.filt_map} data=- numThreads={threads} {params.eval_order} {params.dist_method} &> {log}
        grep -A 100000 \*\*\*\ LG\ \= {log} > {output}
        """

rule reordercheck:
    input:
        expand("reordermarkers/ordered.{lg}.{iter}", lg = lg_range, iter = ITER)
    output:
        "reorder.done"
    shell:
        "touch {output}"