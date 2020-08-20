version 1.0

workflow GetReadSupport {
    input {
        File ref
        File contigs1
        File contigs2
        File reads_list
        File small_variants_ref_contigs1
        File small_variants_contigs1_ref
        File small_variants_ref_contigs2
        File small_variants_contigs2_ref
        File small_variants_contigs1_contigs2
        File small_variants_contigs2_contigs1
    }
    Array[File] reads = read_lines(reads_list)
    scatter (reads_file in reads) {
        call align_source_reads as align_ref {
            input:
                ref=ref,
                reads=reads_file,
        }

        call align_source_reads as align_contigs1 {
            input:
                ref=contigs1,
                reads=reads_file
        }

        call align_source_reads as align_contigs2 {
            input:
                ref=contigs2,
                reads=reads_file
        }

        call get_read_support_small as get_read_support_small_ref_contigs1 {
            input:
                alignment=align_ref.alignment,
                variants=small_variants_ref_contigs1
        }

        call get_read_support_small as get_read_support_small_contigs1_ref {
            input:
                alignment=align_contigs1.alignment,
                variants=small_variants_contigs1_ref
        }

        call collate_read_support as collate_small_variant_support_ref_contigs1 {
            input:
                contig_support=get_read_support_small_ref_contigs1.read_support,
                ref_support=get_read_support_small_contigs1_ref.read_support
        }

        call get_read_support_small as get_read_support_small_ref_contigs2 {
            input:
                alignment=align_ref.alignment,
                variants=small_variants_ref_contigs2
        }

        call get_read_support_small as get_read_support_small_contigs2_ref {
            input:
                alignment=align_contigs2.alignment,
                variants=small_variants_contigs2_ref
        }

        call collate_read_support as collate_small_variant_support_ref_contigs2 {
            input:
                contig_support=get_read_support_small_ref_contigs2.read_support,
                ref_support=get_read_support_small_contigs2_ref.read_support
        }
        call get_read_support_small as get_read_support_small_contigs1_contigs2 {
            input:
                alignment=align_contigs2.alignment,
                variants=small_variants_contigs1_contigs2
        }

        call get_read_support_small as get_read_support_small_contigs2_contigs1 {
            input:
                alignment=align_contigs1.alignment,
                variants=small_variants_contigs2_contigs1
        }

        call collate_read_support as collate_small_variant_support_contigs1_contigs2 {
            input:
                contig_support=get_read_support_small_contigs1_contigs2.read_support,
                ref_support=get_read_support_small_contigs2_contigs1.read_support
        }
    }
    call combine_read_support as combine_small_variant_support_ref_contigs1 {
        input:
            read_support = collate_small_variant_support_ref_contigs1.collated_support
    }
    call combine_read_support as combine_small_variant_support_ref_contigs2 {
        input:
            read_support = collate_small_variant_support_ref_contigs2.collated_support
    }
    call combine_read_support as combine_small_variant_support_contigs1_contigs2 {
        input:
            read_support = collate_small_variant_support_contigs1_contigs2.collated_support
    }

    output {
        File small_variant_support_ref_contigs1 = combine_small_variant_support_ref_contigs1.total_read_support
        File small_variant_support_ref_contigs2 = combine_small_variant_support_ref_contigs2.total_read_support
        File small_variant_support_contigs1_contigs2 = combine_small_variant_support_contigs1_contigs2.total_read_support
    }
}

task align_source_reads {
    input {
        File ref
        File reads
    }
    command <<<
        set -exo pipefail
        MINIMAP2=/opt/hall-lab/minimap2/minimap2
        $MINIMAP2 -t 8 -I 8G -x map-pb --cs ~{ref} ~{reads} > alignment.paf
    >>>
    runtime {
        memory: "32G"
        docker: "apregier/analyze_assemblies@sha256:5cbac56b15b739783c37d2a92261bef138d5bae3e99171557df06d3e39cb485a"
    }
    output {
        File alignment="alignment.paf"
    }
}

task get_read_support_small {
    input {
        File alignment
        File variants
    }
    command <<<
        set -exo pipefail
        PYTHON=/opt/hall-lab/python-2.7.15/bin/python
        READ_COUNT_SCRIPT=/storage1/fs1/ccdg/Active/analysis/ref_grant/assembly_analysis_20200220/multiple_competitive_alignment/read_support_from_paf.py #TODO
        $PYTHON $READ_COUNT_SCRIPT -a ~{alignment} -v ~{variants} > support.txt
    >>>
    runtime {
        memory: "32G"
        docker: "apregier/analyze_assemblies@sha256:adebe7469079606b3d2cd93841e55afa88e749f22090970465057cabebdbd632"
    }
    output {
        File read_support="support.txt"
    }
}

task collate_read_support {
    input {
        File contig_support
        File ref_support
    }
    command <<<
        set -exo pipefail
        PYTHON=/opt/hall-lab/python-2.7.15/bin/python
        BEDTOOLS=/opt/hall-lab/bedtools
        FILTER_SUPPORT_SCRIPT=/storage1/fs1/ccdg/Active/analysis/ref_grant/assembly_analysis_20200220/multiple_competitive_alignment/filter_support.py #TODO
        join <(cat ~{contig_support} | sed 's/\t/ /' | sort) <(cat ~{ref_support} | sed 's/\t/ /' | sort) | sed 's/ /\t/' > collated.txt
        $PYTHON $FILTER_SUPPORT_SCRIPT -i collated.txt | sort | $BEDTOOLS groupby -g 1 -c 3,6 -o sum,sum > support.txt
    >>>
    runtime {
        memory: "32G"
        docker: "apregier/analyze_assemblies@sha256:adebe7469079606b3d2cd93841e55afa88e749f22090970465057cabebdbd632"
    }
    output {
        File collated_support="support.txt"
    }
}

task combine_read_support {
    input {
        Array[File] read_support
    }
    command <<<
        set -exo pipefail
        BEDTOOLS=/opt/hall-lab/bedtools
        cat ~{sep=" " read_support} | sort | $BEDTOOLS groupby -g 1 -c 2,3 -o sum,sum > support.txt
    >>>
    runtime {
        memory: "32G"
        docker: "apregier/analyze_assemblies@sha256:adebe7469079606b3d2cd93841e55afa88e749f22090970465057cabebdbd632"
    }
    output {
        File total_read_support="support.txt"
    }
}
