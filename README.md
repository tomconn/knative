# Local Knative Development on macOS (Apple Silicon/ARM64)

This repository provides a complete guide and all the necessary scripts to set up a local Knative development environment on an Apple Silicon (ARM64) Mac. It uses Rancher Desktop, Minikube, and a custom Go application to demonstrate a real-world CloudEvents workflow.

The core of this setup is a robust shell script that automates the creation and destruction of a fully configured Knative cluster.

- **Platform**: macOS (Apple Silicon/ARM64)
- **Container Runtime**: Rancher Desktop v1.19.3
- **Kubernetes**: Minikube (latest) with Kubernetes `v1.32.6`
- **Knative**: Serving & Eventing `v1.18.0`
- **Go**: `v1.24`

## Table of Contents

1.  [Prerequisites](#1-prerequisites)
2.  [Environment Setup](#2-environment-setup)
3.  [The Go CloudEvents Application](#3-the-go-cloudevents-application)
4.  [Build and Push the Application Image](#4-build-and-push-the-application-image)
5.  [Deploy and Test the Knative Application](#5-deploy-and-test-the-knative-application)
6.  [Cleanup](#6-cleanup)

---

## 1. Prerequisites

Before you begin, you must install the following tools. We recommend using [Homebrew](https://brew.sh/) for easy installation on macOS.

### a. Rancher Desktop

This provides the Docker environment that Minikube will use.
- **Download and install [Rancher Desktop](https://rancherdesktop.io/)**.
- **Important Configuration**: During the first-run wizard or in `Preferences -> Container Engine`, ensure you select **`dockerd (moby)`** as the container runtime. This is required for Minikube's Docker driver.

### b. Command-Line Tools (via Homebrew)

If you don't have Homebrew, [install it first](https://brew.sh/). Then, open your terminal and run:

```bash
# Install Go (for building the app)
brew install go

# Install Minikube (for the Kubernetes cluster)
brew install minikube

# Install the Knative CLI (kn)
brew install kn
```

`kubectl` and `docker` CLIs are automatically installed and configured by Rancher Desktop.

---

## 2. Environment Setup

This step uses the provided script to create a fully configured Knative cluster on your machine.

### a. Clone the Repository

```bash
git clone https://github.com/tomconn/knative.git
cd knative
```

### b. Make the Scripts Executable

```bash
chmod +x scripts/manage-cluster.sh
```

### c. Start the Knative Cluster

Run the `start` command. This process will take several minutes as it downloads container images and sets up the cluster.

```bash
./scripts/manage-cluster.sh start
```

**🔑 Sudo Password**: You will be prompted for your macOS password one time. This is required for `minikube tunnel` to create a network route from your Mac to the cluster, which is essential for accessing your services.

When the script finishes, you will have a ready-to-use Knative cluster with a "magic" `sslip.io` domain configured for easy access.

---

## 3. The Go CloudEvents Application

This repository includes a sample Go application (`cmd/event-display/main.go`) that acts as a sink for CloudEvents. It's designed to:
- Receive events via HTTP POST requests.
- Parse them using the official CloudEvents Go SDK.
- Log the event's type and source to the console.

It is built to be a native ARM64 binary for compatibility with Apple Silicon hardware.

---

## 4. Build and Push the Application Image

To run our Go app in Knative, we need to build it into a container image and push it to a registry. We will use the GitHub Container Registry (`ghcr.io`).

**Important**: Because our local machine is ARM64, we will perform a **multi-arch build**. This creates an image that works on both ARM64 (like our Mac) and AMD64 (common in cloud environments).

### a. Log in to GitHub Container Registry

You need a GitHub Personal Access Token (PAT) with `write:packages` scope.
1.  [Create a PAT here](https://github.com/settings/tokens/new).
2.  Log in via the Docker CLI, using your GitHub username and the PAT as the password.

```bash
# Replace <YOUR_GITHUB_USERNAME> with your actual username
export GITHUB_USER="<YOUR_GITHUB_USERNAME>"
export GITHUB_TOKEN="<YOUR_PERSONAL_ACCESS_TOKEN>"

echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USER --password-stdin
```

### b. Build and Push the Multi-Arch Image

The `docker buildx` command handles building for multiple platforms and pushing in a single step.

```bash
# Define the image name
export IMAGE_NAME="ghcr.io/${GITHUB_USER}/knative-event-display:latest"

# Build for both ARM64 and AMD64 and push to the registry
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --tag $IMAGE_NAME \
  --push \
  .
```

Your container image is now available at your public GitHub Packages repository.

---

## 5. Deploy and Test the Knative Application

Now we will deploy two Knative components:
1.  A `PingSource` that generates a new CloudEvent every minute.
2.  Our `event-display` service to receive and log these events.

### a. Deploy the PingSource and the Service

Create a file named `deploy.yaml` with the following content. **Remember to replace `<YOUR_GITHUB_USERNAME>`** with your actual GitHub username.

```yaml
# deploy.yaml
apiVersion: sources.knative.dev/v1
kind: PingSource
metadata:
  name: cron-ping-source
spec:
  schedule: "* * * * *" # Every minute
  contentType: "application/json"
  data: '{"message": "Hello from PingSource!"}'
  sink:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: event-display
---
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: event-display
spec:
  template:
    spec:
      containers:
        - image: ghcr.io/<YOUR_GITHUB_USERNAME>/knative-event-display:latest # <-- IMPORTANT: REPLACE THIS
          ports:
            - containerPort: 8080
          env:
            - name: PORT
              value: "8080"
```

Apply this configuration to your cluster:

```bash
kubectl apply -f deploy.yaml
```

### b. Verify the Setup

Wait about a minute for the first ping event to be sent. We can watch the logs of our `event-display` pod to see the events as they arrive.

```bash
# This command will follow the logs of your running application
kubectl logs -l serving.knative.dev/service=event-display -c user-container --follow
```

You should see output similar to this, appearing once every minute:
```
2024/06/27 15:30:00 Received a CloudEvent!
  - Type: dev.knative.sources.ping
  - Source: /apis/v1/namespaces/default/pingsources/cron-ping-source
  - Subject:
  - Data: {"message":"Hello from PingSource!"}
2024/06/27 15:31:00 Received a CloudEvent!
  - Type: dev.knative.sources.ping
  - Source: /apis/v1/namespaces/default/pingsources/cron-ping-source
  - Subject:
  - Data: {"message":"Hello from PingSource!"}
```

**Congratulations!** You have a fully working local Knative environment receiving and processing CloudEvents.

---

## 6. Cleanup

When you are finished, you can completely remove the cluster and all related resources by running the `destroy` command.

```bash
./scripts/manage-cluster.sh destroy
```

This will stop the tunnel process and delete the Minikube cluster, returning your system to a clean state.


# Prompt

Create demo that uses a bash script to create a minkube cluster to demonstrate an end to end knative example publish/consumer application using cloudevents.io 

The example will be run on MacOS (Apple silicon/ARM64). It will use the latest Rancher Desktop 1.19.3.
The latest minikube will be used as the kubernetes cluster.
The example app should use the latest go version 1.24. 
The example will use the latest knative 1.17. Knative will be setup using brew installing kn and kn-extensions for quickstarts.
Use a minikube cluster to create a knative app that processes cloudevents.io (just simple ping events). The publisher will be invoked with an user inputted string, invoked using curl. The event will be sent to the consumer. The consumer will log the message to standard out. Both the publisher and consumer will scale to zero after 10 minutes of inactivity. 
It will setup and launch
	```# ensure at least 3+ CPU and 4GB+ of RAM
	brew install knative-extensions/kn-plugins/quickstart
	kn quickstart minikube```
	in a seperate process to enable curl calls to the producer.
The golang, event-producer and event-consumer, will be built locally using go cli and the packages tagged and pushed to the public repository https://github.com/tomconn?tab=packages 

```example of build and package deploy to https://github.com/tomconn?tab=packages
# Use the event-producer and event-consumer 
# Build, tag and push
docker login ghcr.io
    <github token classic>

# From the root of your project directory
docker build -t event-producer:v1 ./apps/event-producer
docker build -t event-consumer:v1 ./apps/event-consumer

# tag
docker tag event-producer:v1 ghcr.io/tomconn/event-producer:v1
docker tag event-consumer:v1 ghcr.io/tomconn/event-consumer:v1

# push
docker push ghcr.io/tomconn/event-producer:v1
docker push ghcr.io/tomconn/event-consumer:v1
```

The tunnel will allow access to knative
```
# start tunnel in seperate terminal
minikube tunnel --profile knative
```

The producer/consumer will be accessible from curl and kubectl logs.
```
# using a pod in cluster
kubectl run curl-pod --image=curlimages/curl -- sleep infinity
kubectl exec curl-pod -- curl -s  http://hello.default.svc.cluster.local

# using the loadbalancer
kubectl get ksvc hello
NAME    URL                                       LATESTCREATED   LATESTREADY   READY   REASON
hello   http://hello.default.127.0.0.1.sslip.io   hello-00001     hello-00001   True    
% curl http://hello.default.127.0.0.1.sslip.io
Hello World!

curl http://hello.default.127.0.0.1.sslip.io
```
Provide full instructions on this setup and the example producer/consumer code. 
Generate instructions on creating the golang producer/consumer and how to push to ghcr.io/tomconn. Keep the code simple and modular
Generate a script to create and destroy minikube. The scripts should include the launching and stopping of the minikube tunnel. Ensure the script uses environment variables to allow reuse with other package registeries.
There should be a script for the building, packaging and push to repository of the producer/consumer apps. And another script for the starting and stopping of the minikube knative cluster and tunnels.
Validate all the code and config for syntax and semantic errors.






# kind-knative
Use a minikube cluster to create a knative app that processes cloudevents.io (simple ping events)

Install
1. Rancher Desktop
	# add the location of docker if using Rancher Desktop
	export DOCKER_HOST=unix:///Users/thomasconnolly/.rd/docker.sock
2. Install 


brew install knative/client/kn

# ensure 3+ CPU and 4GB+ of RAM
brew install knative-extensions/kn-plugins/quickstart
kn quickstart minikube

# start tunnel in seperate terminal
minikube tunnel --profile knative


# using a pod in cluster
kubectl run curl-pod --image=curlimages/curl -- sleep infinity
kubectl exec curl-pod -- curl -s  http://hello.default.svc.cluster.local

# using the LB
kubectl get ksvc hello
NAME    URL                                       LATESTCREATED   LATESTREADY   READY   REASON
hello   http://hello.default.127.0.0.1.sslip.io   hello-00001     hello-00001   True    
(base) thomasconnolly@Thomass-MacBook-Air kind-knative % curl http://hello.default.127.0.0.1.sslip.io
Hello World!

curl http://hello.default.127.0.0.1.sslip.io

# Use the event-producer and event-consumer 
# Build, tag and push
docker login ghcr.io
    <github token classic>

# From the root of your project directory
docker build -t event-producer:v1 ./apps/event-producer
docker build -t event-consumer:v1 ./apps/event-consumer

# tag
docker tag event-producer:v1 ghcr.io/tomconn/event-producer:v1
docker tag event-consumer:v1 ghcr.io/tomconn/event-consumer:v1

# push
docker push ghcr.io/tomconn/event-producer:v1
docker push ghcr.io/tomconn/event-consumer:v1



echo "--> Deploying applications with the 'kn' CLI from ghcr.io..."
kn broker create default || true
kn trigger delete event-consumer-trigger --namespace default || true
kn service delete event-producer --namespace default || true
kn service delete event-consumer --namespace default || true

export DOCKER_USERNAME="tomconn"

kn service create event-consumer --image "ghcr.io/${DOCKER_USERNAME}/event-consumer:v1"
kn service create event-producer --image "ghcr.io/${DOCKER_USERNAME}/event-producer:v1" --env K_SINK="http://default-broker.default.svc.cluster.local"
kn trigger create event-consumer-trigger --broker default --sink ksvc:event-consumer

echo -e "\n\n✅🏆 VICTORY ACHIEVED 🏆✅"
echo "The demo is ready."
echo "\nSend an event: curl http://event-producer.default.127.0.0.1.sslip.io"
echo "\nCheck logs:   kubectl logs -l serving.knative.dev/service=event-consumer -c user-container"