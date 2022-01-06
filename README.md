# DevOPS Assignment Task 1
## Fixing The Vue App

To fix the vue app, I only edit the following code in vue.config.js become:
```js
module.exports = {
    publicPath: '/progressive-weather-app/',
    pwa: {
        themeColor: '#6CB9C8',
        msTileColor: '#484F60'
    },
    css: {
	extract: false,
    },
    configureWebpack: {
        optimization: {
            splitChunks: false
        }
    }
}
```
So for this part:
```js
    css: {
	extract: false,
    },
```
It will inlining css into bundle js. 

And then for this part:
```js
    configureWebpack: {
        optimization: {
            splitChunks: false
        }
    }
```
It will merging vendor and app js. 

And after that I run the following command to update all packages needed by npm:
```sh
npm install
npm update
```
After all packages installed and updated to the latest package, and then I have to build the package:
```sh
npm run build
```
And then the result is under dist directory. For the next step, I will copy the "dist" directory to nginx directory. 

## Preparing for setup Docker the Vue App
I created the following Dockerfile in the root directory:
```sh
ROM nginx:latest

MAINTAINER Muhammad Azmi Farih "muhazmifarih@gmail.com"

COPY nginx/default.conf /etc/nginx/conf.d/
COPY /dist /usr/share/nginx/html/progressive-weather-app
CMD ["nginx", "-g", "daemon off;"]
EXPOSE 80
```
I copy nginx/default.conf for nginx configuration. And then folder "dist" to nginx root folder.  

For building the image and push to docker image registry, I use the following command:
```sh
docker build -t azmifarih/weatherapp .
docker login -u azmifarih -p {password}
docker push azmifarih/weatherapp
```

## Prepare Jenkins

I built Jenkins with the following command:
```sh
docker run \
  --name jenkins-docker \
  --rm \
  --detach \
  --privileged \
  --env DOCKER_TLS_CERTDIR = "" \
  --publish 2375:2375 \
  docker:dind 
```
So, I run the docker from image docker:dind. So it's basically only docker. It will be used for docker server when I want to build docker for Jenkins pipeline. I will keep use docker without tls with port 2375 to make it simple. 

And then run the Jenkins the following command:
```sh
docker run \
  --name jenkins \
  --rm \
  --detach \
  --publish 8080:8080 \
  --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --storage-driver overlay2 \
  jenkins/jenkins:lts-jdk11
```
It will run jenkins based on image jenkins/jenkins:lts-jdk11. And then publish port 8080 to access Jenkins GUI. And then port 50000 for Jenkins agent. I create volume jenkins-data to make persistance data. And use storage driver with overlay2. 

### Prepare Kubernetes

I created the following deployment and service configuration with name weatherapp-kubernetes.yaml :
```sh
apiVersion: apps/v1
kind: Deployment
metadata:
  name: weatherapp
spec:
  replicas: 2
  minReadySeconds: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1  
  selector:
    matchLabels:
      app: weatherapp
  template:
    metadata:
      labels:
        app: weatherapp
    spec:
      terminationGracePeriodSeconds: 5
      containers:
      - name: weatherapp 
        image: azmifarih/weatherapp:<BUILD_TAG>
        imagePullPolicy: Always
        ports:
          - containerPort: 80
            protocol: TCP
            name: web
---
apiVersion: v1
kind: Service
metadata:
  name: weatherapp
spec:
  externalName: weatherapp
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: weatherapp
  type: ClusterIP
---
apiVersion: autoscaling/v1
kind: HorizontalPodAutoscaler
metadata:
  name: weatherapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: weatherapp
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 70
```
I use only two replica with maxUnavailable is one and maxSurge is one as well. So, the maximum pod during the deployment update is three and the minimum pod is one. And then using image from the Vue app. For first setup, please remove ":<BUILD_TAG>". I use Service type ClusterIP because I will use ingress controller for public interface. And then the answer for auto scalling, I use hpa based on CPU utilization percentage. Please use the following command to apply Deployment and Service configuration:
```sh
kubectl apply -f weatherapp-kubernetes.yaml
```

For the next step, I will configure nginx ingress controller. Run the following command to it:
```sh
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install nginx-ingress ingress-nginx/ingress-nginx --set controller.publishService.enabled=true
```
I use cert-manager as well for securing the ingress. Before continue, I create my subdomain to point it to IP of loadbalancer via A record. Please use the following command to install cert-manager:
```sh
kubectl create namespace cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
```
Then I create ClusterIssuer configuration with the file name production_issuer.yaml that contain:
```sh
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # Email address used for ACME registration
    email: muhazmifarih@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Name of a secret used to store the ACME account private key
      name: letsencrypt-private-weatherapp
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
    - http01:
        ingress:
          class: nginx
```
Please keep metadata name for next configuration. And then privateKeySecretRef name should be different every you create new ClusterIssuer. Please use the following command to apply ClusterIssuer configuration:
```sh
kubectl apply -f production_issuer.yaml
```
And then deploy ingress configuration using weatherapp-ingress.yaml:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: weatherapp-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - weatherapp.muhammadazmifarih.my.id
    secretName: weatherapp-tls
  rules:
  - host: "weatherapp.muhammadazmifarih.my.id"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: weatherapp
            port:
              number: 80
```
cert-manager.io/cluster-issuer use previous metadata name from cluster issuer. And then I use weatherapp.muhammadazmifarih.my.id as my hosts. And this ingress have backend to the Vue app that I already deployed. Please use the following command to apply ingress configuration:
```sh
kubectl apply -f weatherapp-ingress.yaml
```

### Preparing CI/CD Jenkins

#### Plugin Junkins
First of all, I install NodeJS Plugin, Docker Plugin, and Kubernetes Plugin on Jenkins via GUI. 
For NodeJS Plugin, I need it to run npm command on the jenkins agent. To configure it, please use the following step:
- Click "Manage Jenkins"
- Click "Global Tool Configuration"
- Click "Add NodeJS"
- Fill name with "Node"
- And then click install automatically
- Choose version 10.24.0
- Click Save

For Docker Plugin, I need it also to run docker command on the jenkins agent. To configure it, please use the following step:
- Click "Manage Jenkins"
- Click "Global Tool Configuration"
- Click "Add Docker
- Fill name with "Docker
- And then click install automatically
- Click Add Installer then choose "Download from docker.com"
- Click Save

I need that both of plugin later for creating Jenkinsfile.

For Kubernetes Plugin, I need it to connect between Jenkins with Kubernetes. I will only use kubernetes as a node cloud, and there is no another nodes. To configure it, please use the following step:
- Click "Manage Jenkins"
- Click "Manage Nodes and Clouds"
- Click "Configure Clouds"
- Click "Add a new cloud" and then choose Kubernetes
- Fill name with "kubernetes"
- Click "Kubernetes Cloud details"
- For Kubernetes URL, check with the following command:
```sh
kubectl cluster-info
```
- Click "Disable https certificate check"
- Fill "Kubernetes Namespace" with "jenkins"
- For "Credentials", please run the following command first:
```sh
kubectl create serviceaccount jenkins --namespace=jenkins && kubectl describe secret $(kubectl describe serviceaccount jenkins --namespace=jenkins | grep Token | awk '{print $2}') --namespace=jenkins && kubectl create rolebinding jenkins-admin-binding --clusterrole=admin --serviceaccount=jenkins:jenkins --namespace=jenkins
```
- And add a secret text with the token output from previous command
- Choose a secret text created in "Credentials"
- Fill Jenkins URL with the IP address of Jenkins with port 8080
- Fill Jenkins tunnel with the IP address of Jenkins with port 50000
- Click Pod Templates
- Fill Name with "jnlp"
- Fill Labels with "jnlp"
- Click Save

#### Configuring Jenkins Pipeline
- Click New Item
- Enter an item name with "pipeline_jenkins"
- Click pipeline
- Click OK
- Click Pipeline from SCM
- Choose Git in SCM
- Fill Repository user with https://github.com/azmifarih/syb-task-1.git
- And then click save 
- I configure it manually for the trigger

I will explain about Jenkinsfile I use:
```sh
podTemplate(containers: [
    containerTemplate(name: 'jnlp', image: 'azmifarih/inbound-agent')]) {
    node(POD_LABEL) {
			env.NODEJS_HOME = "${tool 'Node'}"
			env.DOCKER_HOME = "${tool 'Docker'}"
            env.DOCKER_HOST = "tcp://159.223.36.160:2375"
            env.DOCKER_TLS_CERTDIR = ""
			env.PATH="${env.NODEJS_HOME}/bin:${env.DOCKER_HOME}/bin:${env.PATH}"

			stage('Prepare') {
				echo "1.Prepare Stage"
				checkout([$class: 'GitSCM', branches: [[name: '*/master']], extensions: [], userRemoteConfigs: [[url: 'https://github.com/azmifarih/progressive-weather-app.git']]])
				script {
					build_tag = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
					if (env.BRANCH_NAME != 'master') {
						build_tag = "${env.BRANCH_NAME}-${build_tag}"
					}
				}
			}
			stage('Compile') {
				echo "2.Compile VueJs"
				sh "npm install"
				sh "npm run build"
			}
			stage('Build') {
					echo "3.Build Docker Image Stage"
					sh "docker build -t azmifarih/weatherapp:${build_tag} ."
			}
			stage('Push') {
					echo "4.Push Docker Image Stage"
					withCredentials([usernamePassword(credentialsId: 'dockerhub_id', passwordVariable: 'dockerHubPassword', usernameVariable: 'dockerHubUser')]) {
						sh "docker login -u ${dockerHubUser} -p ${dockerHubPassword}"
						sh "docker push azmifarih/weatherapp:${build_tag}"
					}
			}
			stage('Deploy') {
				echo "5. Deploy To K8S Cluster Stage"
				sh "sed -i 's/<BUILD_TAG>/${build_tag}/' weatherapp-kubernetes.yaml"
				withKubeConfig([credentialsId: '832e0400-f81a-4b09-9c71-21c308382c06',
				        serverUrl: 'https://a60269ca-c388-41ef-96d2-6ffb5b94d747.k8s.ondigitalocean.com']) {
                    				sh 'curl -LO "https://storage.googleapis.com/kubernetes-release/release/v1.20.5/bin/linux/amd64/kubectl"'  
                    				sh 'chmod u+x ./kubectl'  
                    				sh './kubectl apply -f weatherapp-kubernetes.yaml --record'
                			}
			}
		}
}
```
For image azmifarih/inbound-agent, I add a curl command from image jenkins/agent. I use file docker-inbound-agent/Dockerfile:
```sh
ARG version=4.10-6-jdk17-preview
FROM jenkins/agent:$version

ARG version
LABEL Description="This is a base image, which allows connecting Jenkins agents via JNLP protocols" Vendor="Jenkins project" Version="$version"

ARG user=jenkins

USER root
COPY ./curl /usr/local/bin/curl
COPY ./jenkins-agent /usr/local/bin/jenkins-agent
RUN chmod +x /usr/local/bin/jenkins-agent /usr/local/bin/curl &&\
    ln -s /usr/local/bin/jenkins-agent /usr/local/bin/jenkins-slave
USER ${user}

ENTRYPOINT ["/usr/local/bin/jenkins-agent"]
```

For the pipeline:
1. Prepare Stage
It will clone the source of the Vue app from github and create a tag. 
2. Compile VueJs
Run command to install and build the package. The output will be directory "dist".
3. Build Docker Image Stage
Build docker image with tag from first stage.
4. Push Docker Image Stage
Push docker image stage with tag from first stage.
5. Deploy To K8S Cluster Stage
Deploy image from fourth stage to kubernetes cluster. 