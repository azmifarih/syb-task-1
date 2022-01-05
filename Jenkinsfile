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
