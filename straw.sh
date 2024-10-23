#!/bin/bash

# Set strict error handling
set -euo pipefail

# Function to display usage information
usage() {
    echo "Usage: $0 [-t TOKEN] [-o] [-u] <name>"
    echo "Options:"
    echo "  -t TOKEN    GitHub personal access token (recommended)"
    echo "  -o         Force organization mode"
    echo "  -u         Force user mode"
    echo "  -h         Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 microsoft          # Auto-detect if microsoft is a user or org"
    echo "  $0 -o microsoft       # Force microsoft to be treated as an org"
    echo "  $0 -u john           # Force john to be treated as a user"
    echo "  $0 -t <token> google  # Use with GitHub token (recommended)"
    exit 1
}

# Function to handle errors
handle_error() {
    echo "Error: $1" >&2
    exit 1
}

# Function to check if name is an organization
check_if_org() {
    local name=$1
    local response
    response=$(curl "${CURL_OPTS[@]}" "https://api.github.com/orgs/$name" 2>/dev/null)
    if echo "$response" | grep -q '"type": "Organization"'; then
        return 0  # It's an organization
    else
        return 1  # It's not an organization
    fi
}

# Function to fetch repositories
fetch_repos() {
    local type=$1
    local name=$2
    local page=$3
    local per_page=$4
    
    if [ "$type" = "org" ]; then
        echo "Fetching organization repositories..."
        curl "${CURL_OPTS[@]}" "https://api.github.com/orgs/$name/repos?page=$page&per_page=$per_page"
    else
        echo "Fetching user repositories..."
        curl "${CURL_OPTS[@]}" "https://api.github.com/users/$name/repos?page=$page&per_page=$per_page"
    fi
}

# Parse command line options
TOKEN=""
FORCE_ORG=false
FORCE_USER=false

while getopts "t:ouh" opt; do
    case $opt in
        t) TOKEN=$OPTARG ;;
        o) FORCE_ORG=true ;;
        u) FORCE_USER=true ;;
        h) usage ;;
        \?) usage ;;
    esac
done

# Shift past the options
shift $((OPTIND-1))

# Check if a name is provided
if [ $# -eq 0 ]; then
    usage
fi

NAME=$1
PAGE=1
PER_PAGE=100
REPOS_LIST=()
CURL_OPTS=(-s)

# Add authorization header if token is provided
if [ -n "$TOKEN" ]; then
    CURL_OPTS+=(-H "Authorization: token $TOKEN")
else
    echo "Warning: Running without a token may hit API rate limits. Use -t option to provide a token."
fi

# Determine if target is organization or user
if $FORCE_ORG; then
    TYPE="org"
elif $FORCE_USER; then
    TYPE="user"
else
    if check_if_org "$NAME"; then
        echo "$NAME is an organization"
        TYPE="org"
    else
        echo "$NAME is a user"
        TYPE="user"
    fi
fi

echo "Fetching repositories for $TYPE: $NAME"

# Fetch all repositories across all pages
while : ; do
    # Make API request with error handling
    RESPONSE=$(fetch_repos "$TYPE" "$NAME" "$PAGE" "$PER_PAGE") || handle_error "Failed to fetch repositories"
    
    # Check for API rate limiting
    if echo "$RESPONSE" | grep -q "API rate limit exceeded"; then
        handle_error "GitHub API rate limit exceeded. Please provide a token using -t option."
    fi

    # Extract repository URLs
    REPOS=$(echo "$RESPONSE" | grep -o '"clone_url": "[^"]*"' | cut -d'"' -f4) || true
    
    # Break if no more repositories are found
    if [ -z "$REPOS" ]; then
        break
    fi
    
    # Accumulate repositories in the list
    REPOS_LIST+=($REPOS)
    
    # Increment page number
    PAGE=$((PAGE + 1))
    
    echo "Found $(echo "$REPOS" | wc -l) repositories on page $((PAGE-1))"
done

# Check if any repositories were found
if [ ${#REPOS_LIST[@]} -eq 0 ]; then
    handle_error "No repositories found for $TYPE: $NAME"
fi

echo "Total repositories found: ${#REPOS_LIST[@]}"

# Create a directory for the repositories
mkdir -p "$NAME" || handle_error "Failed to create directory: $NAME"
cd "$NAME" || handle_error "Failed to change to directory: $NAME"

# Clone or update repositories
for repo in "${REPOS_LIST[@]}"; do
    repo_name=${repo%.git}
    repo_name=${repo_name#https://github.com/*/}  # Handle both user and org URLs
    
    if [ -d "$repo_name" ]; then
        echo "Updating repository: $repo_name"
        (cd "$repo_name" && git pull) || echo "Warning: Failed to update $repo_name"
    else
        echo "Cloning repository: $repo_name"
        git clone "$repo" || echo "Warning: Failed to clone $repo_name"
    fi
done

echo "Finished processing all repositories"







## # Auto-detect if it's an organization or user
#  ./script.sh microsoft

# Force organization mode
# ./script.sh -o microsoft

# Force user mode
# ./script.sh -u someuser

# With GitHub token (recommended, especially for organizations)
# ./script.sh -t your_github_token microsoft
