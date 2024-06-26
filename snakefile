configfile: "./config.yml"

rule quality_control:
	input:
		r1 = "samples/{sample}_1.fastq",
		r2 = "samples/{sample}_2.fastq"
	output:
		c1 = "clean/{sample}_1P.fastq",
		c2 = "clean/{sample}_2P.fastq"
	params:
		cores = config["cores"]
	shell:
		"""
		printf "\n### Quality control for {wildcards.sample} ###\n\n"	

		trimmomatic PE -threads {params.cores} -basein {input.r1} -baseout clean/{wildcards.sample}.fastq ILLUMINACLIP:adapters.fa:2:30:10:2:keepBothReads SLIDINGWINDOW:4:28 MINLEN:75

		rm clean/*U.fastq

		"""

rule host_mapping:
	input:
		c1 = "clean/{sample}_1P.fastq",
		c2 = "clean/{sample}_2P.fastq"
	output:
		u1 = "unmapped/{sample}_1.fastq",
		u2 = "unmapped/{sample}_2.fastq"
	params:
		genome_dir = config["genome_dir"],
		cores = config["cores"]
	shell:
		"""
		
		printf  "\n###Mapping paired reads of {wildcards.sample} to host###\n\n"

		STAR --runThreadN {params.cores} --genomeDir {params.genome_dir} --sjdbGTFfile {params.genome_dir}/*.gtf --sjdbOverhang 150 -- readFilesIn {input} --outSAMtype BAM SortedByCoordinate --outSAMstrandField intronMotif --outFileNamePrefix unmapped/{wildcards.sample}_mapped --quantMode GeneCounts --outSAMunmapped Within

		printf  "\n###Mapped paired reads of {wildcards.sample} to host###\n\n"

		mv unmapped/{wildcards.sample}_mapped*.bam unmapped/{wildcards.sample}_mapped.bam

		printf  "\n###Extracing unmapped reads###\n\n"

		samtools view -b -f 4 unmapped/{wildcards.sample}_mapped.bam > unmapped/{wildcards.sample}_unmapped.bam

		bedtools bamtofastq -i unmapped/{wildcards.sample}_unmapped.bam -fq {output.u1} -fq2 {output.u2}
		
		"""

rule assembly:
	input:
		u1 = "unmapped/{sample}_1.fastq",
		u2 = "unmapped/{sample}_2.fastq"
	output:
		a1 = "assembly/{sample}_contigs.fasta",
		a2 = "assembly/{sample}_contigs.gfa"
	params:
		cores = config["cores"],
		kmers = config["kmers"]
	shell:
		"""

		printf  "\n###De novo assembly of unmapped reads of {wildcards.sample}###\n\n" 

		rnaspades.py -1 {input.u1} -2 {input.u2} -k 51 -o assembly/{wildcards.sample}/ --threads {params.cores} --memory 60 -k {params.kmers} 

		mv assembly/{wildcards.sample}/transcripts.fasta {output.a1}

		mv assembly/{wildcards.sample}/*scaffolds.gfa {output.a2}

		rm -rf assembly/{wildcards.sample}

		"""

rule annotate_contigs:
	input:
		"assembly/{sample}_contigs.fasta"
	output:
		"annot/{sample}_contigs.gbk",
		"annot/{sample}_contigs.fna"
	params:
		outdir = "annot/contig/",
		prefix = "contigs",
		cores = config["cores"]
	conda:
		"envs/prokka.yml"
	shell:
		"""
		
		printf  "\n###Annotating {wildcards.sample} assembled {params.prefix} with prokka###\n\n"


		prokka --addgenes --outdir {params.outdir} --locustag {wildcards.sample} --kingdom Viruses --prefix {wildcards.sample}_{params.prefix} --metagenome --mincontiglen 1 --cpus {params.cores} --centre X --compliant --norrna --notrna {input}

		mv {params.outdir}{wildcards.sample}_{params.prefix}.gbk annot/{wildcards.sample}_{params.prefix}.gbk

		mv {params.outdir}{wildcards.sample}_{params.prefix}.fna annot/{wildcards.sample}_{params.prefix}.fna

		rm -r {params.outdir}

		"""

rule contig_clustering:
	input:
		"assembly/{sample}_contigs.fasta"
	output:
		"clusters/{sample}_repr.fasta"
	shell:
		"""
		
		printf  "\n###Getting representative sequences from assembled contigs of {wildcards.sample} using CD-HIT###\n\n"

		cd-hit-est -i {input} -o clusters/{wildcards.sample} -c 0.95 -n 8

		mv clusters/{wildcards.sample} {output}
	
		"""

use rule annotate_contigs as annotate_clusters with:
	input:
		"clusters/{sample}_repr.fasta"
	output:
		"annot/{sample}_clusters.gbk",
		"annot/{sample}_clusters.fna"
	params:
		outdir = "annot/cluster/",
		prefix = "clusters",
		cores = config["cores"]

rule virus_mapping:
	input:
		"annot/{sample}_contigs.fna"
	output:
		v1 = "viralmap/contig/{sample}_mapped2virus.fastq",
		v2 = "viralmap/contig/{sample}_mapped2virus.fasta",
		v3 = "viralmap/contig/{sample}_mapped2virus_sorted.bam"
	params:
		database = config["virus_db"],
		org = "viruses",
		outdir = "viralmap/contig/",
		tag = "mapped2virus",
		cores = config["cores"]
	shell:
		"""
		printf  "\n###Mapping {wildcards.sample} assembled contigs to {params.org} database###\n\n"

		minimap2 -ax splice --cs -C5 -L -t {params.cores} {params.database} {input} > {params.outdir}{wildcards.sample}_aln.sam

		samtools view -b -F 4 {params.outdir}{wildcards.sample}_aln.sam > {params.outdir}{wildcards.sample}_{params.tag}.bam

		bedtools bamtofastq -i {params.outdir}{wildcards.sample}_{params.tag}.bam -fq {output.v1}

		sed -n '1~4s/^@/>/p;2~4p' {output.v1} > {output.v2}

		samtools sort {params.outdir}{wildcards.sample}_{params.tag}.bam -o {output.v3}

		samtools index -b {output.v3}

		rm {params.outdir}*.sam {params.outdir}{wildcards.sample}_{params.tag}.bam

		"""

use rule virus_mapping as virus_mapping_clus with:
	input:
		"annot/{sample}_clusters.fna"
	output:
		v1 = "viralmap/cluster/{sample}_mapped2virus.fastq",
		v2 = "viralmap/cluster/{sample}_mapped2virus.fasta",
		v3 = "viralmap/cluster/{sample}_mapped2virus_sorted.bam"
	params:
		database = config["virus_db"],
		org = "viruses",
		outdir = "viralmap/cluster/",
		tag = "mapped2virus",
		cores = config["cores"]

use rule virus_mapping as host_mapping_2 with:
	input:
		"annot/{sample}_contigs.fna"
	output:
		v1 = "humanmap/{sample}_mapped2human.fastq",
		v2 = "humanmap/{sample}_mapped2human.fasta",
		v3 = "humanmap/{sample}_mapped2human_sorted.bam"
	params:
		database = config["human_minimap"],
		org = "human",
		outdir = "humanmap/",
		tag = "mapped2human",
		cores = config["cores"]


rule results:
	input:
		f1 = "annot/{sample}_contigs.gbk",
		f2 = "viralmap/contig/{sample}_mapped2virus_sorted.bam"
	output:
		r1 = "results/contig/{sample}_aln.csv"
	params:
		script = "annot_resume.py",
		outdir = "results/contig",
		tag = "contig"
	conda:
		"envs/results.yml"
	shell:
		"""

		printf  "\n###Generating result files for {params.tag}###\n\n"

		python scripts/{params.script} {input.f1} {wildcards.sample} {input.f2} {params.outdir} {params.tag}

		"""

use rule results as results_cluster with:
	input:
		f1 = "annot/{sample}_clusters.gbk",
		f2 = "viralmap/cluster/{sample}_mapped2virus_sorted.bam"
	output:
		r1 = "results/cluster/{sample}_aln.csv"
	params:
		script = "annot_resume.py",
		outdir = "results/cluster",
		tag = "cluster"

use rule results as results_int with:
	input:
		f1 = "annot/{sample}_contigs.gbk",
		f2 = "humanmap/{sample}_mapped2human_sorted.bam",
		f3 = "results/contig/{sample}_aln.csv"
	output:
		r1 = "results/contig/{sample}_int_aln.csv",
		r2 = "results/contig/{sample}_int_id.csv"
	params:
		script = "annot_int.py",
		outdir = "results/contig",
		tag = "integration"


rule plot_results:
	input:
		p1 = "results/contig/{sample}_aln.csv",
		p2 = "results/cluster/{sample}_aln.csv"
	output:
		"{sample}_log.a"
	conda:
		"envs/plot_results.yml"
	shell:
		"""

		printf  "\n###Generating result plots for contigs###\n\n"

		Rscript --vanilla scripts/Plot.R {input.p1}  results/contig/plots/{wildcards.sample}/

		printf  "\n###Generating result plots for clusters###\n\n"

		Rscript --vanilla scripts/Plot.R {input.p2}  results/cluster/plots/{wildcards.sample}/

		echo "Workflow runned properly for {wildcards.sample}" > {output}

		"""

rule plot_int:
	input:
		"results/contig/{sample}_int_id.csv"
	output:
		"{sample}_int_log.a"
	conda:
		"envs/plot_results.yml"
	shell:
		"""

		printf  "\n###Generating result plots for integration sites###\n\n"

		Rscript --vanilla scripts/Plot_int.R {input}  results/contig/plots/{wildcards.sample}/

		echo "Workflow runned properly for integration sites in {wildcards.sample}" > {output}

		"""

