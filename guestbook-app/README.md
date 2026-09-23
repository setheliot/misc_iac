# Guestbook App

The code and configuration here create an sample guestbook app as a container image and push it to an ECR repository (creating the repository if necessary).

Run `build_image.sh` to generate the container image(s) for ECS, EKS, or Lambda

After installing `requirements.txt`, run the four offline tests with
`python3 -m pytest src/test_app.py` (Python 3.10+).
