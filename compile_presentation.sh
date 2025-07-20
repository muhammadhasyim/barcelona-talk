#!/bin/bash

# Compile script for Barcelona talk presentation
# This script handles the full compilation process for a beamer presentation with biblatex
# Added support for compiling specific slides or ranges

set -e  # Exit on any error

# Configuration
MAIN_FILE="presentation"
OUTPUT_DIR="output"
LOG_FILE="compile.log"
TEMP_FILE=""
SLIDE_SELECTION=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to cleanup temporary files
cleanup() {
    if [ -n "$TEMP_FILE" ] && [ -f "$TEMP_FILE" ]; then
        rm -f "$TEMP_FILE"
        print_status "Cleaned up temporary file: $TEMP_FILE"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Function to validate slide numbers
validate_slide_range() {
    local input="$1"
    
    # Check if it's a single label (e.g., "a.1")
    if [[ "$input" =~ ^[a-z]\.[0-9]+$ ]]; then
        return 0
    fi
    
    # Check if it's a range (e.g., "a.1-a.3")
    if [[ "$input" =~ ^[a-z]\.[0-9]+-[a-z]\.[0-9]+$ ]]; then
        return 0
    fi
    
    # Check if it's a comma-separated list (e.g., "a.1,b.2,d.1" or "a.1,b.1-b.3,d.1")
    if [[ "$input" =~ ^[a-z0-9.,\-]+$ ]]; then
        return 0
    fi
    
    return 1
}

# Function to create temporary tex file with slide selection
create_temp_file() {
    local slides="$1"
    TEMP_FILE="${MAIN_FILE}_temp.tex"
    
    print_status "Creating temporary file with slide selection: $slides"
    
    # Find where \begin{document} is and insert \includeonlyframes before it
    local doc_line=$(grep -n "begin{document}" "$MAIN_FILE.tex" | cut -d: -f1)
    
    if [ -z "$doc_line" ]; then
        print_error "Could not find \\begin{document} in $MAIN_FILE.tex"
        return 1
    fi
    
    # Create the temporary file by processing the original
    # First, copy everything up to \begin{document}
    head -n $((doc_line - 1)) "$MAIN_FILE.tex" > "$TEMP_FILE"
    
    # Insert the \includeonlyframes command with the provided labels
    echo "" >> "$TEMP_FILE"
    echo "% Temporary slide selection for compilation" >> "$TEMP_FILE"
    echo "\\includeonlyframes{$slides}" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    
    # Then copy from \begin{document} onwards
    tail -n +$doc_line "$MAIN_FILE.tex" >> "$TEMP_FILE"
    
    print_success "Temporary file created: $TEMP_FILE"
    print_status "Selected frames: $slides"
}

# Check required tools
print_status "Checking required LaTeX tools..."

if ! command_exists pdflatex; then
    print_error "pdflatex not found. Please install a LaTeX distribution (e.g., TeX Live, MiKTeX)"
    exit 1
fi

if ! command_exists biber; then
    print_warning "biber not found. Bibliography compilation may fail if needed."
fi

# Create output directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
    print_status "Created output directory: $OUTPUT_DIR"
fi

# Function to run pdflatex
run_pdflatex() {
    local pass_name="$1"
    local tex_file="${2:-$MAIN_FILE}"
    print_status "Running pdflatex ($pass_name) on $tex_file.tex..."
    
    if pdflatex -interaction=nonstopmode -output-directory="$OUTPUT_DIR" "$tex_file.tex" >> "$LOG_FILE" 2>&1; then
        print_success "pdflatex ($pass_name) completed successfully"
        return 0
    else
        print_error "pdflatex ($pass_name) failed. Check $LOG_FILE for details"
        return 1
    fi
}

# Function to run biber
run_biber() {
    local base_name="${1:-$MAIN_FILE}"
    print_status "Running biber for bibliography..."
    
    if biber "$OUTPUT_DIR/$base_name" >> "$LOG_FILE" 2>&1; then
        print_success "biber completed successfully"
        return 0
    else
        print_warning "biber failed or no bibliography found. This may be normal if no citations exist."
        return 1
    fi
}

# Function to check for compilation errors
check_errors() {
    if grep -q "! " "$LOG_FILE"; then
        print_error "LaTeX errors found in compilation:"
        grep "! " "$LOG_FILE" | head -5
        return 1
    fi
    return 0
}

# Function to check for warnings
check_warnings() {
    local warning_count=$(grep -c "Warning" "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$warning_count" -gt 0 ]; then
        print_warning "Found $warning_count warnings (this is usually normal for beamer presentations)"
    fi
}

# Main compilation process
main() {
    local compile_file="$MAIN_FILE"
    local output_suffix=""
    
    # Handle slide selection
    if [ -n "$SLIDE_SELECTION" ]; then
        create_temp_file "$SLIDE_SELECTION"
        compile_file="${MAIN_FILE}_temp"
        output_suffix="_slides_$(echo "$SLIDE_SELECTION" | tr ',' '_' | tr '-' 'to')"
        print_status "Compiling selected slides: $SLIDE_SELECTION"
    else
        print_status "Compiling all slides"
    fi
    
    print_status "Starting compilation of $compile_file.tex"
    print_status "Log file: $LOG_FILE"
    
    # Clear previous log
    > "$LOG_FILE"
    
    # First pass
    if ! run_pdflatex "first pass" "$compile_file"; then
        check_errors
        exit 1
    fi
    
    # Check if bibliography is needed and run biber
    if grep -q "\\bibliography\|\\addbibresource\|\\cite" "$compile_file.tex" || find . -name "*.bib" -type f | grep -q .; then
        print_status "Bibliography detected, running biber..."
        run_biber "$compile_file"
    else
        print_status "No bibliography detected, skipping biber"
    fi
    
    # Second pass (after biber)
    if ! run_pdflatex "second pass" "$compile_file"; then
        check_errors
        exit 1
    fi
    
    # Third pass (to resolve all references)
    if ! run_pdflatex "third pass" "$compile_file"; then
        check_errors
        exit 1
    fi
    
    # Check for errors and warnings
    check_errors
    check_warnings
    
    # Rename output file if slide selection was used
    local final_output="$OUTPUT_DIR/$MAIN_FILE$output_suffix.pdf"
    if [ -n "$SLIDE_SELECTION" ] && [ -f "$OUTPUT_DIR/$compile_file.pdf" ]; then
        mv "$OUTPUT_DIR/$compile_file.pdf" "$final_output"
    elif [ -f "$OUTPUT_DIR/$compile_file.pdf" ]; then
        final_output="$OUTPUT_DIR/$compile_file.pdf"
    fi
    
    # Check if PDF was created successfully
    if [ -f "$final_output" ]; then
        local pdf_size=$(du -h "$final_output" | cut -f1)
        print_success "Compilation completed successfully!"
        print_success "Output PDF: $final_output (Size: $pdf_size)"
        
        # Optional: Open PDF if on macOS
        if [[ "$OSTYPE" == "darwin"* ]] && command_exists open; then
            print_status "Opening PDF..."
            open "$final_output"
        fi
    else
        print_error "PDF file was not created. Check $LOG_FILE for details"
        exit 1
    fi
}

# Function to clean auxiliary files
clean() {
    print_status "Cleaning auxiliary files..."
    
    # Remove common LaTeX auxiliary files from output directory
    find "$OUTPUT_DIR" -name "*.aux" -o -name "*.log" -o -name "*.out" -o -name "*.toc" \
         -o -name "*.nav" -o -name "*.snm" -o -name "*.fls" -o -name "*.fdb_latexmk" \
         -o -name "*.bbl" -o -name "*.bcf" -o -name "*.blg" -o -name "*.run.xml" \
         -o -name "*.synctex.gz" | xargs rm -f 2>/dev/null || true
    
    # Remove temporary files
    rm -f "${MAIN_FILE}_temp.tex" 2>/dev/null || true
    
    print_success "Auxiliary files cleaned"
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

COMMANDS:
  (no args)     Compile the entire presentation
  clean         Remove auxiliary files
  help          Show this help message

OPTIONS:
  -s, --slides SELECTION    Compile only specified slides using frame labels
                           Examples:
                             -s a.1           (compile slide a.1 only)
                             -s a.1,b.2,d.1   (compile slides a.1, b.2, and d.1)
                             -s a.1-a.3       (compile slides a.1 through a.3)
                             -s a.1,b.1-b.3,d.1  (compile complex combinations)

SLIDE LABELS:
  Part A (Introduction & Framework):
    a.1 - Introduction to supercooled liquids
    a.2 - Dynamical facilitation theory background  
    a.3 - EDF theory comprehensive overview

  Part B (Excitations Theory):
    b.1 - Pure shear excitations
    b.2 - Excitation results (shear modulus)
    b.3 - Excitation results (numerical validation)

  Part C (2D Onset Temperature):
    c.1 - Mean-squared displacement introduction
    c.2 - Geometric charges and excitation nature
    c.6 - Energy-entropy framework
    c.7 - Melting scenario  
    c.8 - Numerical results
    c.10 - Mermin-Wagner finite-size effects
    c.13 - Keim experimental validation
    c.15 - Spatial correlations

  Part D (Facilitation Theory):
    d.1 - Facilitation general idea
    d.2 - Facilitation interaction mechanism
    d.4 - Dynamical heterogeneity results
    d.5 - Emergent glassy dynamics
    d.6 - Role of phonons

  Part E (Conclusion):
    e.1 - Acknowledgements

EXAMPLES:
  $0                        # Compile all slides
  $0 -s a.1                 # Compile only introduction slide
  $0 -s a.1,a.2,a.3         # Compile Part A (introduction)
  $0 -s b.1-b.3             # Compile Part B (excitations)
  $0 -s a.1,b.1,d.1         # Compile key overview slides
  $0 clean                  # Clean auxiliary files

NOTE: When using slide selection, the output PDF will be named with a suffix
      indicating which slides were compiled (e.g., presentation_slides_a1.pdf)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--slides)
            if [ -z "$2" ]; then
                print_error "Option $1 requires an argument"
                exit 1
            fi
            if ! validate_slide_range "$2"; then
                print_error "Invalid slide selection format: $2"
                print_error "Use numbers, ranges (5-10), or comma-separated lists (1,3,5-8)"
                exit 1
            fi
            SLIDE_SELECTION="$2"
            shift 2
            ;;
        clean)
            clean
            exit 0
            ;;
        help|-h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
done

# Run main compilation
main