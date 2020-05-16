rule separatechromosomes:
    input:
        "data_f.call.gz"
    output:
        map = "maps.splitchrom/map.{lod_range}"
    message:
        """
        Creating maps for specified LOD range >> maps.splitchrom/map.LG
        """
    threads: config["SepChrom_threads"]
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