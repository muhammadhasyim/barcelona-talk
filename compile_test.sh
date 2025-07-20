#!/bin/bash

# Compile script for Barcelona talk presentation
# This script handles the full compilation process for a beamer presentation with biblatex
# Now supports selective slide compilation

set -e  # Exit on any error

# Configuration
MAIN_FILE="presentation"
OUTPUT_DIR="output"
LOG_FILE="compile.log"
TEMP_FILE=""
COMPILE_MODE="all"
SELECTED_SLIDES=""

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

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  (no args)     Compile the entire presentation"
    echo "  clean         Remove auxiliary files"
    echo "  help          Show this help message"
    echo ""
    echo "Slide Selection Options:"
    echo "  --slide N             Compile only slide N"
    echo "  --slides N,M,P        Compile only slides N, M, and P"
    echo "  --range N-M           Compile slides N through M (inclusive)"
    echo "  --list                List all frame numbers and titles"
    echo ""
    echo "Examples:"
    echo "  $0                    # Compile all slides"
    echo "  $0 --slide 5          # Compile only slide 5"
    echo "  $0 --slides 1,3,7     # Compile slides 1, 3, and 7"
    echo "  $0 --range 5-10       # Compile slides 5 through 10"
    echo "  $0 --list             # Show all frame titles"
}

# Function to list all frames with numbers
list_frames() {
    print_status "Analyzing frames in $MAIN_FILE.tex..."
    
    local frame_count=0
    local in_frame=false
    local frame_title=""
    
    # Process main file and included files
    while IFS= read -r line; do
        # Check for input statements to follow included files
        if [[ $line =~ \\input\{([^}]+)\} ]]; then
            local input_file="${BASH_REMATCH[1]}"
            if [[ ! $input_file =~ \.tex$ ]]; then
                input_file="${input_file}.tex"
            fi
            
            if [[ -f "$input_file" ]]; then
                while IFS= read -r subline; do
                    if [[ $subline =~ \\begin\{frame\} ]] || [[ $subline =~ \\begin\{frame\}\[.*\] ]]; then
                        ((frame_count++))
                        in_frame=true
                        frame_title=""
                    elif [[ $subline =~ \\frametitle\{([^}]*)\} ]] && [[ $in_frame == true ]]; then
                        frame_title="${BASH_REMATCH[1]}"
                        printf "%3d: %s\n" "$frame_count" "$frame_title"
                        in_frame=false
                    elif [[ $subline =~ \\end\{frame\} ]] && [[ $in_frame == true ]]; then
                        if [[ -z "$frame_title" ]]; then
                            printf "%3d: (No title)\n" "$frame_count"
                        fi
                        in_frame=false
                    fi
                done < "$input_file"
            fi
        elif [[ $line =~ \\begin\{frame\} ]] || [[ $line =~ \\begin\{frame\}\[.*\] ]]; then
            ((frame_count++))
            in_frame=true
            frame_title=""
        elif [[ $line =~ \\frametitle\{([^}]*)\} ]] && [[ $in_frame == true ]]; then
            frame_title="${BASH_REMATCH[1]}"
            printf "%3d: %s\n" "$frame_count" "$frame_title"
            in_frame=false
        elif [[ $line =~ \\end\{frame\} ]] && [[ $in_frame == true ]]; then
            if [[ -z "$frame_title" ]]; then
                printf "%3d: (No title)\n" "$frame_count"
            fi
            in_frame=false
        fi
    done < "$MAIN_FILE.tex"
    
    print_success "Found $frame_count frames total"
}

# Function to parse slide selection
parse_slides() {
    local input="$1"
    local slides=()
    
    if [[ $input =~ ^[0-9]+-[0-9]+$ ]]; then
        # Range format: N-M
        local start="${input%-*}"
        local end="${input#*-}"
        for ((i=start; i<=end; i++)); do
            slides+=("$i")
        done
    else
        # Comma-separated format: N,M,P
        IFS=',' read -ra slides <<< "$input"
    fi
    
    # Convert to space-separated string
    echo "${slides[@]}"
}

# Function to create selective compilation file
create_selective_file() {
    local slides_array=($1)
    TEMP_FILE="${MAIN_FILE}_selective.tex"
    
    print_status "Creating selective compilation file for slides: ${slides_array[*]}"
    
    # Copy preamble from original file
    sed '/\\begin{document}/q' "$MAIN_FILE.tex" > "$TEMP_FILE"
    
    # Track current frame number
    local current_frame=0
    local in_frame=false
    local skip_frame=false
    local frame_content=""
    
    # Process main file and included files
    while IFS= read -r line; do
        if [[ $line =~ \\input\{([^}]+)\} ]]; then
            local input_file="${BASH_REMATCH[1]}"
            if [[ ! $input_file =~ \.tex$ ]]; then
                input_file="${input_file}.tex"
            fi
            
            if [[ -f "$input_file" ]]; then
                while IFS= read -r subline; do
                    if [[ $subline =~ \\begin\{frame\} ]] || [[ $subline =~ \\begin\{frame\}\[.*\] ]]; then
                        ((current_frame++))
                        in_frame=true
                        frame_content="$subline"
                        
                        # Check if this frame should be included
                        skip_frame=true
                        for target in "${slides_array[@]}"; do
                            if [[ $current_frame -eq $target ]]; then
                                skip_frame=false
                                break
                            fi
                        done
                    elif [[ $in_frame == true ]]; then
                        frame_content="$frame_content"$'\n'"$subline"
                        
                        if [[ $subline =~ \\end\{frame\} ]]; then
                            if [[ $skip_frame == false ]]; then
                                echo "$frame_content" >> "$TEMP_FILE"
                                echo "" >> "$TEMP_FILE"
                            fi
                            in_frame=false
                            frame_content=""
                        fi
                    elif [[ $skip_frame == false ]]; then
                        echo "$subline" >> "$TEMP_FILE"
                    fi
                done < "$input_file"
            fi
        elif [[ $line =~ \\begin\{frame\} ]] || [[ $line =~ \\begin\{frame\}\[.*\] ]]; then
            ((current_frame++))
            in_frame=true
            frame_content="$line"
            
            # Check if this frame should be included
            skip_frame=true
            for target in "${slides_array[@]}"; do
                if [[ $current_frame -eq $target ]]; then
                    skip_frame=false
                    break
                fi
            done
        elif [[ $in_frame == true ]]; then
            frame_content="$frame_content"$'\n'"$line"
            
            if [[ $line =~ \\end\{frame\} ]]; then
                if [[ $skip_frame == false ]]; then
                    echo "$frame_content" >> "$TEMP_FILE"
                    echo "" >> "$TEMP_FILE"
                fi
                in_frame=false
                frame_content=""
            fi
        elif [[ ! $line =~ \\input\{ ]] && [[ $skip_frame == false ]] && [[ $in_frame == false ]]; then
            echo "$line" >> "$TEMP_FILE"
        elif [[ ! $line =~ \\input\{ ]] && [[ $current_frame -eq 0 ]]; then
            # Include non-frame content before any frames
            echo "$line" >> "$TEMP_FILE"
        fi
    done < "$MAIN_FILE.tex"
    
    print_success "Created selective compilation file: $TEMP_FILE"
}

# Function to cleanup temporary files
cleanup_temp() {
    if [[ -n "$TEMP_FILE" ]] && [[ -f "$TEMP_FILE" ]]; then
        rm -f "$TEMP_FILE"
        print_status "Cleaned up temporary file: $TEMP_FILE"
    fi
}

# Check required tools
check_tools() {
    print_status "Checking required LaTeX tools..."

    if ! command_exists pdflatex; then
        print_error "pdflatex not found. Please install a LaTeX distribution (e.g., TeX Live, MiKTeX)"
        exit 1
    fi

    if ! command_exists biber; then
        print_warning "biber not found. Bibliography compilation may fail if needed."
    fi
}

# Create output directory if it doesn't exist
setup_output_dir() {
    if [ ! -d "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
        print_status "Created output directory: $OUTPUT_DIR"
    fi
}

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
    local tex_file="${1:-$MAIN_FILE}"
    print_status "Running biber for bibliography..."
    
    if biber "$OUTPUT_DIR/$tex_file" >> "$LOG_FILE" 2>&1; then
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
compile_presentation() {
    local tex_file="${1:-$MAIN_FILE}"
    local output_suffix=""
    
    if [[ "$COMPILE_MODE" != "all" ]]; then
        output_suffix="_selective"
        print_status "Compiling selected slides: $SELECTED_SLIDES"
    fi
    
    print_status "Starting compilation of $tex_file.tex"
    print_status "Log file: $LOG_FILE"
    
    # Clear previous log
    > "$LOG_FILE"
    
    # First pass
    if ! run_pdflatex "first pass" "$tex_file"; then
        check_errors
        cleanup_temp
        exit 1
    fi
    
    # Check if bibliography is needed and run biber
    if grep -q "\\bibliography\|\\addbibresource\|\\cite" "$tex_file.tex" || find . -name "*.bib" -type f | grep -q .; then
        print_status "Bibliography detected, running biber..."
        run_biber "$tex_file"
    else
        print_status "No bibliography detected, skipping biber"
    fi
    
    # Second pass (after biber)
    if ! run_pdflatex "second pass" "$tex_file"; then
        check_errors
        cleanup_temp
        exit 1
    fi
    
    # Third pass (to resolve all references)
    if ! run_pdflatex "third pass" "$tex_file"; then
        check_errors
        cleanup_temp
        exit 1
    fi
    
    # Check for errors and warnings
    check_errors
    check_warnings
    
    # Check if PDF was created successfully
    if [ -f "$OUTPUT_DIR/$tex_file.pdf" ]; then
        local pdf_size=$(du -h "$OUTPUT_DIR/$tex_file.pdf" | cut -f1)
        print_success "Compilation completed successfully!"
        print_success "Output PDF: $OUTPUT_DIR/$tex_file.pdf (Size: $pdf_size)"
        
        # Rename if selective compilation
        if [[ "$COMPILE_MODE" != "all" ]]; then
            local final_name="$OUTPUT_DIR/${MAIN_FILE}${output_suffix}.pdf"
            mv "$OUTPUT_DIR/$tex_file.pdf" "$final_name"
            print_success "Renamed to: $final_name"
            
            # Optional: Open PDF if on macOS
            if [[ "$OSTYPE" == "darwin"* ]] && command_exists open; then
                print_status "Opening PDF..."
                open "$final_name"
            fi
        else
            # Optional: Open PDF if on macOS
            if [[ "$OSTYPE" == "darwin"* ]] && command_exists open; then
                print_status "Opening PDF..."
                open "$OUTPUT_DIR/$tex_file.pdf"
            fi
        fi
    else
        print_error "PDF file was not created. Check $LOG_FILE for details"
        cleanup_temp
        exit 1
    fi
    
    cleanup_temp
}

# Function to clean auxiliary files
clean() {
    print_status "Cleaning auxiliary files..."
    
    # Remove common LaTeX auxiliary files from output directory
    find "$OUTPUT_DIR" -name "*.aux" -o -name "*.log" -o -name "*.out" -o -name "*.toc" \
         -o -name "*.nav" -o -name "*.snm" -o -name "*.fls" -o -name "*.fdb_latexmk" \
         -o -name "*.bbl" -o -name "*.bcf" -o -name "*.blg" -o -name "*.run.xml" \
         -o -name "*.synctex.gz" | xargs rm -f 2>/dev/null || true
    
    # Remove temporary selective files
    rm -f "${MAIN_FILE}_selective.tex"
    
    print_success "Auxiliary files cleaned"
}

# Main script logic
main() {
    check_tools
    setup_output_dir
    
    if [[ "$COMPILE_MODE" == "all" ]]; then
        compile_presentation
    else
        local slides_array=($(parse_slides "$SELECTED_SLIDES"))
        create_selective_file "${slides_array[*]}"
        compile_presentation "${MAIN_FILE}_selective"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --slide)
            COMPILE_MODE="selective"
            SELECTED_SLIDES="$2"
            shift 2
            ;;
        --slides)
            COMPILE_MODE="selective"
            SELECTED_SLIDES="$2"
            shift 2
            ;;
        --range)
            COMPILE_MODE="selective"
            SELECTED_SLIDES="$2"
            shift 2
            ;;
        --list)
            list_frames
            exit 0
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

# Run main compilation if no command was given
main
