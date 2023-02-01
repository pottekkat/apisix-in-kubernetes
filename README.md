# APISIX in Kubernetes

This document contains instructions for the tutorial _APISIX in Kubernetes_. For a detailed guide, see the series [Hands-On With Apache APISIX Ingress](https://navendu.me/series/hands-on-with-apache-apisix-ingress/).

## Setup Environment

Before you proceed to the tutorial, make sure you have:

1. Access to a Kubernetes cluster. This tutorial uses [minikube](https://minikube.sigs.k8s.io/docs/start/) for creating a local cluster.
2. Install and configure kubectl for communicating with the Kubernetes cluster.
3. Install [Helm](https://helm.sh/docs/intro/quickstart/) to deploy APISIX.

## Install APISIX Ingress

APISIX and APISIX Ingress controller can be installed using Helm:

```shell
helm repo add apisix https://charts.apiseven.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create ns ingress-apisix
helm install apisix apisix/apisix \
  --set gateway.type=NodePort \
  --set ingress-controller.enabled=true \
  --namespace ingress-apisix \
  --set ingress-controller.config.apisix.serviceNamespace=ingress-apisix
kubectl get pods --namespace ingress-apisix
```

## Expose APISIX to Host

If you are using minikube, you can expose APISIX by running:

```shell
minikube service apisix-gateway --url -n ingress-apisix
```

You can use the shown URL to access `apisix-gateway` service.

## Deploy a Sample Application

Our sample application, [bare-minimum-api](https://github.com/navendu-pottekkat/bare-minimum-api) can be installed in Kubernetes by running:

```shell
kubectl run bare-minimum-api-v1 --image navendup/bare-minimum-api --port 8080 -- 8080 v1.0
kubectl expose pod bare-minimum-api-v1 --port 8080
kubectl run bare-minimum-api-v2 --image navendup/bare-minimum-api --port 8080 -- 8080 v2.0
kubectl expose pod bare-minimum-api-v2 --port 8080
```

## Create a Route

The [ApisixRoute](https://apisix.apache.org/docs/ingress-controller/concepts/apisix_route/) resource will create a Route to direct traffic between the two "versions" of our sample application ([sample-route-crd.yaml](./sample-route-crd.yaml)):

```yaml
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  name: api-routes
spec:
  http:
    - name: route-1
      match:
        hosts:
          - local.navendu.me
        paths:
          - /v1
      backends:
        - serviceName: bare-minimum-api-v1
          servicePort: 8080
    - name: route-2
      match:
        hosts:
          - local.navendu.me
        paths:
          - /v2
      backends:
        - serviceName: bare-minimum-api-v2
          servicePort: 8080
```

You can then apply this configuration:

```shell
kubectl apply -f sample-route-crd.yaml
```

Here is the same configuration using the default Kubernetes Ingress resource ([sample-route-ingress.yaml](./sample-route-ingress.yaml)):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-routes
spec:
  ingressClassName: apisix
  rules:
    - host: local.navendu.me
      http:
        paths:
          - backend:
              service:
                name: bare-minimum-api-v1
                port:
                  number: 8080
            path: /v1
            pathType: Exact
          - backend:
              service:
                name: bare-minimum-api-v2
                port:
                  number: 8080
            path: /v2
            pathType: Exact
```

## Test the Created Route

You can send a request to APISIX and it will be routed to the backend service based on the created Route:

```shell
curl http://127.0.0.1:51538/v2 -H 'host:local.navendu.me'
```

## Delete the Created Route

You can delete this Route using kubectl:

```shell
kubectl delete -f sample-route-crd.yaml
```

## Create a Canary Release

You can configure a [canary release](https://navendu.me/posts/canary-in-kubernetes/) with the ApisixRoute resource ([canary-release-crd.yaml](./canary-release-crd.yaml)):

```yaml
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  name: canary-release
spec:
  http:
    - name: route-v1
      match:
        paths:
          - /*
      backends:
        - serviceName: bare-minimum-api-v1
          servicePort: 8080
          weight: 100
        - serviceName: bare-minimum-api-v2
          servicePort: 8080
          weight: 0
```

```shell
kubectl apply -f canary-release-crd.yaml
```

## Test Canary Release

You can adjust weights and test how the traffic is split between the two services:

```shell
curl http://127.0.0.1:51538/api -H 'host:local.navendu.me'
```

## Extending APISIX Ingress

### With Annotations

The annotation [k8s.apisix.apache.org/allowlist-source-range](https://apisix.apache.org/docs/ingress-controller/concepts/annotations/#allowlist-source-range) will only allow the whitelisted IP addresses to access the service ([annotation-ingress.yaml](./annotation-ingress.yaml)):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-routes
  annotations:
    k8s.apisix.apache.org/allowlist-source-range: "172.17.0.1"
spec:
  ingressClassName: apisix
  rules:
    - host: local.navendu.me
      http:
        paths:
          - backend:
              service:
                name: bare-minimum-api-v1
                port:
                  number: 8080
            path: /v1
            pathType: Exact
          - backend:
              service:
                name: bare-minimum-api-v2
                port:
                  number: 8080
            path: /v2
            pathType: Exact
```

```shell
kubectl apply -f annotation-ingress.yaml
```

### With Plugins

The [limit-count](https://apisix.apache.org/docs/apisix/plugins/limit-count/) Plugin limits the number of requests to your service ([limit-count-crd.yaml](./limit-count-crd.yaml)):

```yaml
apiVersion: apisix.apache.org/v2
kind: ApisixRoute
metadata:
  name: method-route
spec:
  http:
    - name: method
      match:
        hosts:
          - local.navendu.me
        paths:
          - /api
      backends:
      - serviceName: bare-minimum-api-v1
        servicePort: 8080
        weight: 50
      - serviceName: bare-minimum-api-v2
        servicePort: 8080
        weight: 50
      plugins:
        - name: limit-count
          enable: true
          config:
            count: 10
            time_window: 10
```

### Test the Plugin

You can test by sending multiple requests:

```shell
for i in {1..20}
do
    curl http://127.0.0.1:57761/api -H 'host:local.navendu.me'
done
```

## Use Kubernetes Gateway API

The [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) also works with Apache APISIX Ingress.

First you have to enable it. You can do this while installing APISIX via Helm:

```shell
helm repo add apisix https://charts.apiseven.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create ns ingress-apisix
helm install apisix apisix/apisix --namespace ingress-apisix \
--set gateway.type=NodePort \
--set ingress-controller.enabled=true \
--set ingress-controller.config.apisix.serviceNamespace=ingress-apisix \
--set ingress-controller.config.kubernetes.enableGatewayAPI=true
```

You also have to install the Gateway API CRDs as they are not installed by default:

```shell
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v0.5.0/standard-install.yaml
```

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: HTTPRoute
metadata:
  name: canary-release
spec:
  hostnames:
  - local.navendu.me
  rules:
  - backendRefs:
    - name: bare-minimum-api-v1
      port: 8080
      weight: 50
    - name: bare-minimum-api-v2
      port: 8080
      weight: 50
```

You can learn more from the series [Hands-On With Apache APISIX Ingress](https://navendu.me/series/hands-on-with-apache-apisix-ingress/).