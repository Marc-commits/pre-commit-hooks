#!/usr/bin/env bash
# annotation_manager.sh - annotation utility for Nostoc sp. PCC 7120
#
# Source of truth:
#   source/anotacion_definitiva_plus_ncRNA_120225.gff  (gene annotation, all 7 replicons)
#   source/NC_003272.1_transcripts.gff                 (ANNOgesic transcripts, NC_003272.1)
#   source/20230909_Nostoc_custom.fasta                (custom proteome, 5,918 proteins)
#   source/genbank/                                    (GCA_000009705.1 reference sequences)
#   source/refseq/                                     (GCF_000009705.1, download target)
#
# Requires on PATH for 'merge' command:
#   merge_gff3.py, view_gff3.py, deduce_UTRs.py (from the gff3 tools project)

set -euo pipefail

VERSION="0.1.0"
AUTHOR="Marc Broghammer"
EMAIL="marc.broghammer@gmx.de"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── default paths (relative to project root) ──────────────────────────────────
SOURCE_GENES="source/anotacion_definitiva_plus_ncRNA_120225.gff"
SOURCE_TRANSCRIPTS="source/NC_003272.1_transcripts.gff"
SOURCE_PROTEINS="source/20230909_Nostoc_custom.fasta"
SOURCE_GBFF="source/chr_7120_anotacion_MBA_261222.gb"
GENOME_FASTA="source/genbank/ncbi_dataset/ncbi_dataset/data/GCA_000009705.1/GCA_000009705.1_ASM970v1_genomic.fna"

GENOME_DIR="genome"
TRANSCRIPTOME_DIR="transcriptome"
PROTEOME_DIR="proteome"
PER_PROTEIN_DIR="proteome/per_protein"

EXPECTED_GENES=6145
EXPECTED_PROTEINS=5918

# ── helpers ───────────────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[annotation_manager] $*"; }
warn() { echo "WARN:  $*" >&2; }

require_tool() {
    local tool="$1" hint="${2:-}"
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: '$tool' not found in PATH." >&2
        [[ -n "$hint" ]] && echo "       $hint" >&2
        exit 1
    fi
}

gff3_linecount() {
    grep -cv '^#' "$1" 2>/dev/null || true
}

# Strip DOS (CRLF) line endings in-place using tr
dos2unix_inline() {
    local src="$1" dst="$2"
    tr -d '\r' < "$src" > "$dst"
}

# ── usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: annotation_manager.sh <command> [options]

Reproducible annotation utility for Nostoc sp. PCC 7120.
Never modifies files in source/ — all output goes to subdirs or stdout.

Commands:
  download  [refseq|genbank]         Check / explain how to download NCBI data
  merge     [--output-dir DIR]       Run full annotation merge pipeline
  split     [genome|proteome]        Split FASTA into per-replicon or per-protein files
  export    [gff3|gbff|tsv]          Generate derived files from source of truth
  add       <gff3_line> [-o FILE]    Append a GFF3 feature; default: stdout
  validate  [--all]                  Run integrity checks on all annotation files
  compare   <file1> <file2>          Feature-type summary diff of two annotation files

Options:
  -h, --help       Show this help and exit
  -V, --version    Show version and exit

Source files (source/):
  anotacion_definitiva_plus_ncRNA_120225.gff  6,145 genes across 7 replicons (2025 definitive)
  NC_003272.1_transcripts.gff                 3,648 ANNOgesic transcripts (NC_003272.1)
  20230909_Nostoc_custom.fasta                5,918 custom UniProt proteins
  chr_7120_anotacion_MBA_261222.gb            PGAP 2020 GenBank (chromosome reference)

Replicon seqid mapping (RefSeq ↔ INSDC):
  NC_003272.1 ↔ BA000019.2  chromosome
  NC_003276.1 ↔ BA000020.2  pCC7120alpha
  NC_003240.1 ↔ AP003602.1  pCC7120beta
  NC_003267.1 ↔ AP003603.1  pCC7120gamma
  NC_003273.1 ↔ AP003604.1  pCC7120delta
  NC_003270.1 ↔ AP003605.1  pCC7120epsilon
  NC_003241.1 ↔ AP003606.1  pCC7120zeta

Examples:
  annotation_manager.sh validate --all
  annotation_manager.sh merge
  annotation_manager.sh split genome
  annotation_manager.sh split proteome
  annotation_manager.sh add 'NC_003272.1\tANNOgesic\ttranscript\t100\t200\t.\t+\t.\tID=t_new' \\
      --output /tmp/updated.gff3
  annotation_manager.sh compare source/anotacion_definitiva_plus_ncRNA_120225.gff \\
      source/genbank/ncbi_dataset/ncbi_dataset/data/GCA_000009705.1/genomic.gff
  annotation_manager.sh export tsv

EOF
}

# ── download ──────────────────────────────────────────────────────────────────
cmd_download() {
    local target="${1:-refseq}"
    case "$target" in
        refseq)
            if command -v datasets &>/dev/null; then
                info "Downloading GCF_000009705.1 to source/refseq/ ..."
                mkdir -p source/refseq
                datasets download genome accession GCF_000009705.1 \
                    --include genome,gff3,gbff,rna,protein,cds \
                    --filename source/refseq/GCF_000009705.1.zip
                unzip -q source/refseq/GCF_000009705.1.zip -d source/refseq/
                info "Done. See source/refseq/ncbi_dataset/"
            else
                cat <<'INSTRUCTIONS'
The NCBI 'datasets' CLI is not installed. To install:

  curl -fsSL https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/LATEST/linux-amd64/datasets \
       -o ~/.local/bin/datasets
  chmod +x ~/.local/bin/datasets

Then re-run:  annotation_manager.sh download refseq

Full instructions: source/refseq/README.md
INSTRUCTIONS
            fi
            ;;
        genbank)
            info "GenBank data (GCA_000009705.1) is already in source/genbank/"
            info "See source/genbank/ncbi_dataset/ for the NCBI datasets package."
            ;;
        *)
            die "Unknown target '$target'. Use: refseq | genbank"
            ;;
    esac
}

# ── merge ─────────────────────────────────────────────────────────────────────
cmd_merge() {
    local output_dir="$TRANSCRIPTOME_DIR"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output-dir) output_dir="$2"; shift 2 ;;
            *) die "Unknown option for merge: $1" ;;
        esac
    done

    for tool in merge_gff3.py view_gff3.py deduce_UTRs.py; do
        require_tool "$tool" \
            "Add the gff3 project tool directory to PATH. See https://github.com/mbroghammer/gff3"
    done

    [[ -f "$SOURCE_GENES" ]] || die "Gene annotation not found: $SOURCE_GENES"
    [[ -f "$SOURCE_TRANSCRIPTS" ]] || die "Transcript annotation not found: $SOURCE_TRANSCRIPTS"

    mkdir -p "$output_dir"

    # Step 1: strip DOS line endings from gene GFF
    local genes_out="$output_dir/7120_genes.gff3"
    info "Converting DOS line endings → $genes_out"
    dos2unix_inline "$SOURCE_GENES" "$genes_out"

    # Step 2: copy transcript GFF (already Unix)
    local transcripts_out="$output_dir/7120_transcripts.gff3"
    info "Copying transcript GFF → $transcripts_out"
    cp "$SOURCE_TRANSCRIPTS" "$transcripts_out"

    # Step 3: merge genes + transcripts
    local merged_out="$output_dir/7120_merged.gff3"
    local unmatched_genes="$output_dir/7120_unmatched_genes.gff3"
    local unmatched_transcripts="$output_dir/7120_unmatched_transcripts.gff3"
    info "Merging genes + transcripts → $merged_out"
    merge_gff3.py \
        --genes "$genes_out" \
        --transcripts "$transcripts_out" \
        --fill-missing-transcripts \
        --unmatched-genes "$unmatched_genes" \
        --unmatched-transcripts "$unmatched_transcripts" \
        -o "$merged_out" \
        2>&1 | tee "$output_dir/7120_merge.log"

    # Step 4: deduce UTRs
    local consensus_out="$output_dir/7120_consensus.gff3"
    info "Deducing UTRs → $consensus_out"
    deduce_UTRs.py "$merged_out" \
        --transcripts "$transcripts_out" \
        -o "$consensus_out" \
        2>&1 | tee "$output_dir/7120_deduce_utrs.log"

    # Step 5: view stats
    info "Generating annotation statistics"
    view_gff3.py "$consensus_out" --tree --stats-csv "$output_dir/7120_consensus_stats.csv" \
        2>&1 | tee "$output_dir/7120_view.log"

    info "Merge complete. Output in $output_dir/"
    info "  merged:    $merged_out"
    info "  consensus: $consensus_out"
    info "  stats:     $output_dir/7120_consensus_stats.csv"
}

# ── split ─────────────────────────────────────────────────────────────────────
cmd_split() {
    local target="${1:-}"
    [[ -n "$target" ]] || die "Specify: split genome | split proteome"

    case "$target" in
        genome)
            require_tool python3
            [[ -f "$GENOME_FASTA" ]] || die "Genome FASTA not found: $GENOME_FASTA"
            mkdir -p "$GENOME_DIR"
            info "Splitting genome FASTA into per-replicon files in $GENOME_DIR/"
            python3 - "$GENOME_FASTA" "$GENOME_DIR" <<'PYEOF'
import sys
from pathlib import Path

# RefSeq NC_ ↔ INSDC mapping (GCA_000009705.1 sequence_report.jsonl)
INSDC_TO_REFSEQ = {
    "BA000019.2": "NC_003272.1",
    "BA000020.2": "NC_003276.1",
    "AP003602.1": "NC_003240.1",
    "AP003604.1": "NC_003273.1",
    "AP003605.1": "NC_003270.1",
    "AP003603.1": "NC_003267.1",
    "AP003606.1": "NC_003241.1",
}
REPLICON_NAMES = {
    "NC_003272.1": "chromosome",
    "NC_003276.1": "pCC7120alpha",
    "NC_003240.1": "pCC7120beta",
    "NC_003273.1": "pCC7120delta",
    "NC_003270.1": "pCC7120epsilon",
    "NC_003267.1": "pCC7120gamma",
    "NC_003241.1": "pCC7120zeta",
}

fasta_in, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
current_refseq = current_lines = None
written = 0

def flush(refseq_id, lines):
    name = REPLICON_NAMES.get(refseq_id, refseq_id)
    out = out_dir / f"{refseq_id}.fna"
    with open(out, 'w') as fh:
        fh.write(f">{refseq_id} Nostoc sp. PCC 7120 {name}\n")
        fh.writelines(lines)
    return str(out)

with open(fasta_in) as fh:
    for line in fh:
        if line.startswith('>'):
            if current_refseq:
                path = flush(current_refseq, current_lines)
                print(f"  {path}")
                written += 1
            insdc_id = line.split()[0][1:]
            current_refseq = INSDC_TO_REFSEQ.get(insdc_id, insdc_id)
            current_lines = []
        else:
            if current_refseq is not None:
                current_lines.append(line)

if current_refseq:
    path = flush(current_refseq, current_lines)
    print(f"  {path}")
    written += 1

print(f"Wrote {written} replicon FASTA files to {out_dir}/")
PYEOF
            ;;

        proteome)
            require_tool python3
            [[ -f "$SOURCE_PROTEINS" ]] || die "Protein FASTA not found: $SOURCE_PROTEINS"
            info "Splitting proteome into per-protein files in $PER_PROTEIN_DIR/"
            python3 "$SCRIPT_DIR/scripts/split_proteome.py" \
                --input "$SOURCE_PROTEINS" \
                --output-dir "$PER_PROTEIN_DIR"
            cp "$SOURCE_PROTEINS" "$PROTEOME_DIR/7120_proteome.faa"
            info "Combined FASTA copied to $PROTEOME_DIR/7120_proteome.faa"
            ;;

        *)
            die "Unknown split target '$target'. Use: genome | proteome"
            ;;
    esac
}

# ── add ───────────────────────────────────────────────────────────────────────
cmd_add() {
    local feature_line="" output="-"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output) output="$2"; shift 2 ;;
            *) feature_line="$1"; shift ;;
        esac
    done

    [[ -n "$feature_line" ]] || die "Provide a GFF3 feature line as the first argument"

    local src="$SOURCE_TRANSCRIPTS"
    [[ -f "$src" ]] || die "Transcript source not found: $src"

    if [[ "$output" == "-" ]]; then
        cat "$src"
        printf '%b\n' "$feature_line"
    else
        cat "$src" > "$output"
        printf '%b\n' "$feature_line" >> "$output"
        info "Written to $output ($(gff3_linecount "$output") data lines)"
    fi
}

# ── validate ──────────────────────────────────────────────────────────────────
cmd_validate() {
    local all_checks=false
    [[ "${1:-}" == "--all" ]] && all_checks=true

    local errors=0

    # 1. GFF3 syntax check (gff3_QC)
    require_tool gff3_QC "Install via: pip install gff3tool"
    for gff in "$SOURCE_GENES" "$SOURCE_TRANSCRIPTS" \
                "$TRANSCRIPTOME_DIR/7120_genes.gff3" \
                "$TRANSCRIPTOME_DIR/7120_consensus.gff3"; do
        [[ -f "$gff" ]] || continue
        info "gff3_QC: $gff"
        if ! gff3_QC --gff "$gff" --output /dev/null 2>&1 | grep -q "^0 error"; then
            warn "gff3_QC reported issues in $gff"
            ((errors++)) || true
        fi
    done

    # 2. FASTA integrity
    require_tool python3
    local fasta_candidates=("$SOURCE_PROTEINS" "$PROTEOME_DIR/7120_proteome.faa" "$GENOME_FASTA")
    while IFS= read -r f; do fasta_candidates+=("$f"); done \
        < <(compgen -G "$GENOME_DIR/*.fna" 2>/dev/null || true)
    for fa in "${fasta_candidates[@]}"; do
        [[ -f "$fa" ]] || continue
        info "FASTA validate: $fa"
        if ! python3 "$SCRIPT_DIR/scripts/validate_fasta.py" "$fa"; then
            ((errors++)) || true
        fi
    done

    # 3. GFF3 seqid ↔ FASTA consistency
    info "GFF3-FASTA seqid consistency"
    if ! python3 "$SCRIPT_DIR/scripts/check_gff_fasta.py" \
            --genome-dir "$GENOME_DIR" \
            "$SOURCE_GENES" "$SOURCE_TRANSCRIPTS"; then
        ((errors++)) || true
    fi

    # 4. Gene count guard
    if [[ -f "$SOURCE_GENES" ]]; then
        local count
        count=$(gff3_linecount "$SOURCE_GENES")
        if [[ "$count" -ne "$EXPECTED_GENES" ]]; then
            warn "Gene count in $SOURCE_GENES: $count (expected $EXPECTED_GENES)"
            $all_checks && ((errors++)) || true
        else
            info "Gene count OK: $count genes"
        fi
    fi

    # 5. Protein count guard
    if [[ -f "$SOURCE_PROTEINS" ]]; then
        local pcount
        pcount=$(grep -c '^>' "$SOURCE_PROTEINS" 2>/dev/null || true)
        if [[ "$pcount" -ne "$EXPECTED_PROTEINS" ]]; then
            warn "Protein count in $SOURCE_PROTEINS: $pcount (expected $EXPECTED_PROTEINS)"
            $all_checks && ((errors++)) || true
        else
            info "Protein count OK: $pcount proteins"
        fi
    fi

    # 6. DOS line ending check on GFF source files
    info "Checking for DOS line endings"
    for gff in "$SOURCE_GENES" "$SOURCE_TRANSCRIPTS"; do
        [[ -f "$gff" ]] || continue
        if grep -qP '\r' "$gff" 2>/dev/null; then
            warn "DOS line endings (CRLF) in $gff — run: annotation_manager.sh merge to convert"
        fi
    done

    if [[ "$errors" -eq 0 ]]; then
        info "All checks passed."
    else
        info "$errors check(s) failed."
        exit 1
    fi
}

# ── export ────────────────────────────────────────────────────────────────────
cmd_export() {
    local format="${1:-gff3}"
    require_tool python3

    case "$format" in
        gff3)
            info "Source GFF3 files are already in source/; generated files in transcriptome/"
            info "Run 'annotation_manager.sh merge' to generate transcriptome/7120_consensus.gff3"
            ;;
        gbff)
            info "Building 7120_consensus.gbff ..."
            python3 "$SCRIPT_DIR/scripts/build_consensus.py" \
                --genes "$SOURCE_GENES" \
                --transcripts "$SOURCE_TRANSCRIPTS" \
                --fasta "$GENOME_FASTA" \
                --output 7120_consensus.gbff \
                --verbose
            ;;
        tsv)
            info "Exporting gene annotation TSV"
            {
                printf 'seqid\tstart\tend\tstrand\ttype\tlocus_tag\told_locus_tag\tgene_biotype\tID\n'
                grep -v '^#' "$SOURCE_GENES" | awk -F'\t' '{
                    split($9,a,";")
                    locus=""; old=""; biotype=""; id=""
                    for (i in a) {
                        if (a[i] ~ /^locus_tag=/) { locus=substr(a[i],11) }
                        if (a[i] ~ /^old_locus_tag=/) { old=substr(a[i],15) }
                        if (a[i] ~ /^gene_biotype=/) { biotype=substr(a[i],13) }
                        if (a[i] ~ /^ID=/) { id=substr(a[i],4) }
                    }
                    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                        $1,$4,$5,$7,$3,locus,old,biotype,id
                }'
            } > 7120_genes.tsv
            info "Written: 7120_genes.tsv ($(wc -l < 7120_genes.tsv) lines)"
            ;;
        *)
            die "Unknown export format '$format'. Use: gff3 | gbff | tsv"
            ;;
    esac
}

# ── compare ───────────────────────────────────────────────────────────────────
cmd_compare() {
    local file1="${1:-}" file2="${2:-}"
    [[ -n "$file1" && -n "$file2" ]] || die "Usage: compare <file1> <file2>"
    [[ -f "$file1" ]] || die "File not found: $file1"
    [[ -f "$file2" ]] || die "File not found: $file2"

    info "Comparing: $file1  vs  $file2"

    local ext1="${file1##*.}" ext2="${file2##*.}"

    _gff_summary() {
        local f="$1" label="$2"
        printf '\n=== %s ===\n' "$label"
        printf 'Lines: %d data / %d total\n' \
            "$(gff3_linecount "$f")" "$(wc -l < "$f")"
        printf '\nFeature type counts:\n'
        grep -v '^#' "$f" | cut -f3 | sort | uniq -c | sort -rn
        printf '\nSeqids:\n'
        grep -v '^#' "$f" | cut -f1 | sort -u
    }

    _gb_summary() {
        local f="$1" label="$2"
        printf '\n=== %s ===\n' "$label"
        printf 'LOCUS records: %d\n' "$(grep -c '^LOCUS' "$f" || true)"
        printf '\nFeature key counts:\n'
        grep -E '^ {5}[a-zA-Z]' "$f" | awk '{print $1}' | sort | uniq -c | sort -rn | head -20
    }

    # dispatch based on extension
    case "$ext1" in
        gff|gff3) _gff_summary "$file1" "$file1" ;;
        gb|gbff|genbank) _gb_summary "$file1" "$file1" ;;
        *) _gff_summary "$file1" "$file1" ;;
    esac

    case "$ext2" in
        gff|gff3) _gff_summary "$file2" "$file2" ;;
        gb|gbff|genbank) _gb_summary "$file2" "$file2" ;;
        *) _gff_summary "$file2" "$file2" ;;
    esac

    # shared locus_tag intersection if both are GFF
    if [[ "$ext1" =~ gff && "$ext2" =~ gff ]]; then
        printf '\n=== Locus tag comparison ===\n'
        local loci1 loci2
        loci1=$(grep -v '^#' "$file1" | grep -oP 'locus_tag=\K[^;]+' | sort -u)
        loci2=$(grep -v '^#' "$file2" | grep -oP 'locus_tag=\K[^;]+' | sort -u)
        printf 'Unique to %s: %d\n' "$file1" \
            "$(comm -23 <(echo "$loci1") <(echo "$loci2") | wc -l)"
        printf 'Unique to %s: %d\n' "$file2" \
            "$(comm -13 <(echo "$loci1") <(echo "$loci2") | wc -l)"
        printf 'In common:  %d\n' \
            "$(comm -12 <(echo "$loci1") <(echo "$loci2") | wc -l)"
    fi
}

# ── dispatch ──────────────────────────────────────────────────────────────────
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -V|--version) echo "annotation_manager.sh $VERSION"; exit 0 ;;
        download)  shift; cmd_download  "$@" ;;
        merge)     shift; cmd_merge     "$@" ;;
        split)     shift; cmd_split     "$@" ;;
        export)    shift; cmd_export    "$@" ;;
        add)       shift; cmd_add       "$@" ;;
        validate)  shift; cmd_validate  "$@" ;;
        compare)   shift; cmd_compare   "$@" ;;
        *)
            echo "ERROR: Unknown command '$1'" >&2
            echo "Run 'annotation_manager.sh --help' for usage." >&2
            exit 1
            ;;
    esac
}

main "$@"
