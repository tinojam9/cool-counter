#!/usr/bin/env bash
set -euo pipefail

[[ -n "${DEBUG-}" ]] && set -x

init() {
  local nginx_url="https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static"
  local action=$1
  local down=${2:-""}

  case $action in

  build)
    docker build -t cool-counter .
    ;;

  local)
    if [[ ! -z "$down" ]]; then
      kill $(pgrep rackup)
      brew services stop redis

      exit 0
    fi

    brew_check_or_install redis
    brew services start redis

    bundle exec rackup -p 4567
    ;;

  docker)
    local network=cool-counter-network

    docker run --name=web --network=$network -d -p 4567:4567 cool-counter
    docker run --name=redis --hostname=redis --network=$network -d redis
    ;;
  
  docker-compose)
    if [[ ! -z "$down" ]]; then
      docker-compose down
      
      exit 0
    fi

    docker-compose up -d
    docker-compose logs -f
    ;;
  
  k8s)
    if [[ ! -z "$down" ]]; then
      kubectl delete namespace cool-namespace
      exit 0
    fi

    # Create cluster + load images
    local cluster=$(kind get clusters)

    if [[ $cluster == "cool-cluster" ]]; then
      echo 'using cluster "cool-cluster" ...'
    else
      kind create cluster --config=k8s/cluster.yaml --name=cool-cluster
    fi
    
    kind --name=cool-cluster load docker-image cool-counter
    kind --name=cool-cluster load docker-image redis    

    kubectl apply -f k8s/namespace.yaml
    
    # Deploy web app
    kubectl apply -f k8s/web-deployment.yaml
    kubectl apply -f k8s/web-service.yaml
    kubectl apply -f k8s/redis-deployment.yaml
    kubectl apply -f k8s/redis-service.yaml
    
    # Expose web app via ingress
    kubectl apply -f "${nginx_url}/mandatory.yaml"
    kubectl apply -f "${nginx_url}/provider/baremetal/service-nodeport.yaml"
    kubectl patch deployments -n ingress-nginx nginx-ingress-controller -p "$(cat k8s/nginx-patch.json)"
    kubectl apply -f k8s/ingress.yaml
    ;;
  esac
}

brew_check_or_install() {
  package=$1

  if brew ls --versions $package > /dev/null; then 
    echo "$package is installed"
  else
    echo "Installing $package..."
    brew install $package
  fi
}

init "$@"
