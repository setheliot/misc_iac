#!/bin/bash
set -e

# Configuration
REPOSITORY_NAME="guestbook-app"

# Parse command line arguments
BUILD_TYPE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --eks|--k8s|eks|k8s)
            BUILD_TYPE="eks"
            shift
            ;;
        --lambda|lambda)
            BUILD_TYPE="lambda"
            shift
            ;;
        --both|both)
            BUILD_TYPE="both"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --eks, --k8s  Build only EKS/Kubernetes version"
            echo "  --lambda      Build only Lambda version"
            echo "  --both        Build both versions"
            echo "  --help, -h    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Get AWS account info
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-us-east-1}

# Display configuration
echo "========================================="
echo "AWS ECR Build Configuration"
echo "========================================="
echo "AWS Account: ${ACCOUNT}"
echo "AWS Region:  ${REGION}"
echo "Repository:  ${REPOSITORY_NAME}"
echo "========================================="
echo ""

# Ask for build type if not specified
if [ -z "$BUILD_TYPE" ]; then
    echo "Which version would you like to build?"
    echo "  1) EKS/Kubernetes only"
    echo "  2) Lambda only"
    echo "  3) Both"
    echo ""
    printf "Enter your choice (1-3): "
    read CHOICE
    
    case $CHOICE in
        1)
            BUILD_TYPE="eks"
            ;;
        2)
            BUILD_TYPE="lambda"
            ;;
        3)
            BUILD_TYPE="both"
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
fi

echo ""
echo "Build type: ${BUILD_TYPE}"
echo ""
printf "Do you want to continue? (y/n): "
read REPLY

if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    echo "Build cancelled."
    exit 1
fi

echo ""
echo "Starting build process..."

# Login to ECR (needed for both)
echo "Logging into ECR..."
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com

# Create repository if it doesn't exist
echo "Ensuring ECR repository exists..."
aws ecr create-repository --repository-name ${REPOSITORY_NAME} --region ${REGION} 2>/dev/null || true


# Build based on selection
if [ "$BUILD_TYPE" = "eks" ] || [ "$BUILD_TYPE" = "both" ]; then
    echo ""
    echo "Building EKS/Kubernetes image..."
    docker build --platform linux/amd64 -f Dockerfile.eks -t ${REPOSITORY_NAME}:eks .
    
    # Tag and push with 'eks' tag
    docker tag ${REPOSITORY_NAME}:eks ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:eks
    echo "Pushing EKS image to ECR..."
    docker push ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:eks
    echo "✅ EKS image pushed: ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:eks"
fi

if [ "$BUILD_TYPE" = "lambda" ] || [ "$BUILD_TYPE" = "both" ]; then
    echo ""
    echo "Building Lambda image..."
    docker build --platform linux/arm64 --provenance=false -f Dockerfile.lambda -t ${REPOSITORY_NAME}:lambda .
    
    # Tag and push with 'lambda' tag
    docker tag ${REPOSITORY_NAME}:lambda ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:lambda
    echo "Pushing Lambda image to ECR..."
    docker push ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:lambda
    echo "✅ Lambda image pushed: ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:lambda"
fi

echo ""
echo "✅ Build complete!"
echo ""
echo "Image URIs:"
if [ "$BUILD_TYPE" = "eks" ] || [ "$BUILD_TYPE" = "both" ]; then
    echo "  EKS:    ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:eks"
fi
if [ "$BUILD_TYPE" = "lambda" ] || [ "$BUILD_TYPE" = "both" ]; then
    echo "  Lambda: ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:lambda"
fi
