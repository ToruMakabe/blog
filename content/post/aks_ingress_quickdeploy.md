+++
Categories = ["Azure"]
Tags = ["Azure", "AKS", "Kubernetes"]
date = "2018-02-10T11:00:00+09:00"
title = "AKSのNginx Ingress Controllerのデプロイで悩んだら"

+++

## 楽したいならhelmで入れましょう
AKSに限った話ではありませんが、Kubernetesにぶら下げるアプリの数が多くなってくると、URLマッピングやTLS終端がしたくなります。方法は色々あるのですが、シンプルな選択肢はNginx Ingress Controllerでしょう。

さて、そのNginx Ingress Contrillerのデプロイは[GitHubのドキュメント](https://github.com/kubernetes/ingress-nginx/blob/master/deploy/README.md)通りに淡々とやればいいのですが、[helm](https://github.com/kubernetes/helm)を使えばコマンド一発です。そのようにドキュメントにも書いてあるのですが、最後の方で出てくるので「それ早く言ってよ」な感じです。

せっかくなので、Azure(AKS)での使い方をまとめておきます。開発ペースやエコシステムの変化が速いので要注意。この記事は2018/2/10に書いています。

## 使い方
helmでNginx Controllerを導入します。helmを使っていなければ、[入れておいてください](https://github.com/kubernetes/helm#install)。デプロイはこれだけ。Chartは[ここ](https://github.com/kubernetes/charts/tree/master/stable/nginx-ingress)。
```
$ helm install stable/nginx-ingress --name my-nginx
```

バックエンドへのつなぎが機能するか、Webアプリを作ってテストします。NginxとApacheを選びました。
```
$ kubectl run nginx --image nginx --port 80
$ kubectl run apache --image httpd --port 80
```

サービスとしてexposeします。
```
$ kubectl expose deployment nginx --type NodePort
$ kubectl expose deployment apache --type NodePort
```

現時点のサービスたちを確認します。
```
$ kubectl get svc
NAME                                     TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)                  AGE
apache                                   NodePort       10.0.244.167   <none>          80:30928/TCP                 14h
kubernetes                               ClusterIP      10.0.0.1       <none>          443/TCP                  79d
my-nginx-nginx-ingress-controller        LoadBalancer   10.0.91.78     13.72.108.187   80:32448/TCP,443:31991/TCP   14h
my-nginx-nginx-ingress-default-backend   ClusterIP      10.0.74.104    <none>          80/TCP                  14h
nginx                                    NodePort       10.0.191.16    <none>          80:30752/TCP                 14h
```

AKSの場合はパブリックIPがNginx Ingress Controllerに割り当てられます。EXTERNAL-IPがpendingの場合は割り当て中なので、しばし待ちます。

割り当てられたら、EXTERNAL-IPをAzure DNSで名前解決できるようにしましょう。Azure CLIを使います。dev.example.comの例です。
```
$ az network dns record-set a add-record -z example.com -g your-dnszone-rg -n dev -a 13.72.108.187
```

TLSが終端できるかも検証したいので、Secretを作ります。証明書とキーはLet's Encryptで作っておきました。
```
$ kubectl create secret tls example-tls --key privkey.pem --cert fullchain.pem
```

ではIngressを構成しましょう。以下をファイル名ingress-nginx-sample.yamlとして保存します。IngressでTLSを終端し、/へのアクセスは先ほどexposeしたNginxのサービスへ、/apacheへのアクセスはApacheへ流します。rewrite-targetをannotaionsで指定するのを、忘れずに。
```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
  name: ingress-nginx-sample
spec:
  rules:
    - host: dev.example.com
      http:
        paths:
          - path: /
            backend:
              serviceName: nginx
              servicePort: 80
          - path: /apache
            backend:
              serviceName: apache
              servicePort: 80
  tls:
    - hosts:
      - dev.example.com
      secretName: example-tls
```

あとは反映するだけ。
```
$ kubectl apply -f ingress-nginx-sample.yaml
```

curlで確認します。
```
$ curl https://dev.example.com
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
[snip]
```

/apacheへのパスも確認します。
```
$ curl https://dev.example.com/apache
<html><body><h1>It works!</h1></body></html>
```

簡単ですね。