from os import path
import glob

configfile: "config.yaml"

# load in parameters set in config.yaml
vcf = config["vcf"]
pedigree = config["pedigree"]
sepchrom_threads = config["SepChrom_threads"]
threads_per = config["threads_per"]
dist_method = config["dist_method"]
edge_len = str(config["edge_length"])
trim_thresh = str(config["trim_cutoff"])
lod_max = str(config["lod_max"])
lod_range = list(range(config["lod_min"], config["lod_max"]+1))
lg_range = list(range(1, config["exp_lg"]+1))
lod_lim = config["lod_limit"]
lod_diff = config["lod_difference"]
ITER = list(range(1,config["iter"]+1))

include: "rules/data_prep.smk"
include: "rules/generate_map.smk"
include: "rules/order.smk"
include: "rules/trim.smk"
include: "rules/reorder.smk"
include: "rules/distances.smk"

rule all:
    input:
        expand("distances/ordered.{lg}.distances", lg = lg_range),
        expand("distances_sexaverage/ordered.{lg}.sexavg", lg = lg_range),
        expand("intervals/ordered.{lg}.intervals", lg = lg_range),
        "ordermarkers/trim.summary"
    message:
        """
        LepMak3r is finished! Good luck with the rest of your analyses!
        """