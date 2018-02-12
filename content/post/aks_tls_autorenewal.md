+++
Categories = ["Azure"]
Tags = ["Azure", "AKS", "Kubernetes"]
date = "2018-02-11T00:20:00+09:00"
title = "AKSのIngress TLS証明書を自動更新する"

+++

## カジュアルな証明書管理方式が欲しい
ChromeがHTTPサイトに対する警告を[強化するそうです](https://japan.cnet.com/article/35100589/)。非HTTPSサイトには、生きづらい世の中になりました。

さてそうなると、TLS証明書の入手と更新、めんどくさいですね。ガチなサイトでは証明書の維持管理を計画的に行うべきですが、検証とかちょっとした用途で立てるサイトでは、とにかくめんどくさい。カジュアルな方式が望まれます。

そこで、Azure Container Service(AKS)で使える気軽な方法をご紹介します。

* TLSはIngress(NGINX Ingress Controller)でまとめて終端
* [Let's Encypt](https://letsencrypt.org/)から証明書を入手
* Kubenetesのアドオンである[cert-manager](https://github.com/jetstack/cert-manager/)で証明書の入手、更新とIngressへの適用を自動化
  * ACME(Automatic Certificate Management Environment)対応
  * cert-managerはまだ歴史の浅いプロジェクトだが、[kube-lego](https://github.com/jetstack/cert-manager/)の後継として期待

なおKubernetes/AKSは開発ペースやエコシステムの変化が速いので要注意。この記事は2018/2/10に書いています。

## 使い方
AKSクラスターと、Azure DNS上に利用可能なゾーンがあることを前提にします。ない場合、それぞれ公式ドキュメントを参考にしてください。

* [Azure Container Service (AKS) クラスターのデプロイ](https://docs.microsoft.com/ja-jp/azure/aks/kubernetes-walkthrough)
* [Azure CLI 2.0 で Azure DNS の使用を開始する](https://docs.microsoft.com/ja-jp/azure/dns/dns-getstarted-cli)

まずAKSにNGINX Ingress Controllerを導入します。helmで入れるのが楽でしょう。[この記事](http://torumakabe.github.io/post/aks_ingress_quickdeploy/)も参考に。
```
$ helm install stable/nginx-ingress --name my-nginx
```

サービスの状況を確認します。NGINX Ingress ControllerにEXTERNAL-IPが割り当てられるまで、待ちます。
```
$ kubectl get svc
NAME                                     TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                     AGE
kubernetes                               ClusterIP      10.0.0.1       <none>           443/TCP                     79d
my-nginx-nginx-ingress-controller        LoadBalancer   10.0.2.105     52.234.148.138   80:30613/TCP,443:30186/TCP   6m
my-nginx-nginx-ingress-default-backend   ClusterIP      10.0.102.246   <none>           80/TCP                     6m
```

EXTERNAL-IPが割り当てられたら、Azure DNSで名前解決できるようにします。Azure CLIを使います。Ingressのホスト名をwww.example.comとする例です。このホスト名で、後ほどLet's Encryptから証明書を取得します。
```
$ az network dns record-set a add-record -z example.com -g your-dnszone-rg -n www -a 52.234.148.138
```

cert-managerのソースをGitHubから取得し、contribからhelm installします。いずれstableを使えるようになるでしょう。なお、このAKSクラスターはまだRBACを使っていないので、"--set rbac.create=false"オプションを指定しています。
```
$ git clone https://github.com/jetstack/cert-manager
$ cd cert-manager/
$ helm install --name cert-manager --namespace kube-system contrib/charts/cert-manager --set rbac.create=false
```

では任意の作業ディレクトリに移動し、以下の内容でマニフェストを作ります。cm-issuer-le-staging-sample.yamlとします。
```
apiVersion: certmanager.k8s.io/v1alpha1
kind: Issuer
metadata:
  name: letsencrypt-staging
  namespace: default
spec:
  acme:
    # The ACME server URL
    server: https://acme-staging.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: hoge@example.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-staging
    # Enable the HTTP-01 challenge provider
    http01: {}
```

証明書を発行してもらうLet's EncryptをIssuerとして登録するわけですが、まずはステージングのAPIエンドポイントを指定しています。Let's Encryptには[Rate Limit](https://letsencrypt.org/docs/rate-limits/)があり、失敗した時に痛いからです。Let's EncryptのステージングAPIを使うとフェイクな証明書(Fake LE Intermediate X1)が発行されますが、流れの確認やマニフェストの検証は、できます。

なお、Let's Encryptとのチャレンジには今回、HTTPを使います。DNSチャレンジも[いずれ対応する見込み](https://github.com/jetstack/cert-manager/pull/246)です。

では、Issuerを登録します。
```
$ kubectl apply -f cm-issuer-le-staging-sample.yaml
```

次は証明書の設定です。マニフェストはcm-cert-le-staging-sample.yamlとします。acme節にACME構成を書きます。チャレンジはHTTP、ingressClassはnginxです。
```
apiVersion: certmanager.k8s.io/v1alpha1
kind: Certificate
metadata:
  name: example-com
  namespace: default
spec:
  secretName: example-com-tls
  issuerRef:
    name: letsencrypt-staging
  commonName: www.example.com
  dnsNames:
  - www.example.com
  acme:
    config:
    - http01:
        ingressClass: nginx
      domains:
      - www.example.com
```

証明書設定をデプロイします。
```
$ kubectl apply -f cm-cert-le-staging-sample.yaml
```

証明書の発行状況を確認します。
```
$ kubectl describe certificate example-com
Name:         example-com
Namespace:    default
[snip]
Events:
  Type     Reason                 Age              From                     Message
  ----     ------                 ----             ----                     -------
  Warning  ErrorCheckCertificate  8m               cert-manager-controller  Error checking existing TLS certificate: secret "example-com-tls" not found
  Normal   PrepareCertificate     8m               cert-manager-controller  Preparing certificate with issuer
  Normal   PresentChallenge       8m               cert-manager-controller  Presenting http-01 challenge for domain www.example.com
  Normal   SelfCheck              8m               cert-manager-controller  Performing self-check for domain www.example.com
  Normal   ObtainAuthorization    7m               cert-manager-controller  Obtained authorization for domain www.example.com
  Normal   IssueCertificate       7m               cert-manager-controller  Issuing certificate...
  Normal   CeritifcateIssued      7m               cert-manager-controller  Certificated issuedsuccessfully
  Normal   RenewalScheduled       7m (x2 over 7m)  cert-manager-controller  Certificate scheduled for renewal in 1438 hours
```

無事に証明書が発行され、更新もスケジュールされました。手順やマニフェストの書きっぷりは問題なさそうです。これをもってステージング完了としましょう。

ではLet's EncryptのAPIエンドポイントをProduction向けに変更し、新たにIssuer登録します。cm-issuer-le-prod-sample.yamlとします。
```
apiVersion: certmanager.k8s.io/v1alpha1
kind: Issuer
metadata:
  name: letsencrypt-prod
  namespace: default
spec:
  acme:
    # The ACME server URL
    server: https://acme-v01.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: hoge@example.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    http01: {}
```

デプロイします。
```
$ kubectl apply -f cm-issuer-le-prod-sample.yaml
```

同様に、Production向けの証明書設定をします。cm-cert-le-prod-sample.yamlとします。
```
apiVersion: certmanager.k8s.io/v1alpha1
kind: Certificate
metadata:
  name: prod-example-com
  namespace: default
spec:
  secretName: prod-example-com-tls
  issuerRef:
    name: letsencrypt-prod
  commonName: www.example.com
  dnsNames:
  - www.example.com
  acme:
    config:
    - http01:
        ingressClass: nginx
      domains:
      - www.example.com
```

デプロイします。
```
$ kubectl apply -f cm-cert-le-prod-sample.yaml
```

発行状況を確認します。
```
$ kubectl describe certificate prod-example-com
Name:         prod-example-com
Namespace:    default
[snip]
Events:
  Type     Reason                 Age              From                     Message
  ----     ------                 ----             ----                     -------
  Warning  ErrorCheckCertificate  27s              cert-manager-controller  Error checking existing TLS certificate: secret "prod-example-com-tls" not found
  Normal   PrepareCertificate     27s              cert-manager-controller  Preparing certificate with issuer
  Normal   PresentChallenge       26s              cert-manager-controller  Presenting http-01 challenge for domain www.example.com
  Normal   SelfCheck              26s              cert-manager-controller  Performing self-check for domain www.example.com
  Normal   IssueCertificate       7s               cert-manager-controller  Issuing certificate...
  Normal   ObtainAuthorization    7s               cert-manager-controller  Obtained authorization for domain www.example.com
  Normal   RenewalScheduled       6s (x3 over 5m)  cert-manager-controller  Certificate scheduled for renewal in 1438 hours
  Normal   CeritifcateIssued      6s               cert-manager-controller  Certificated issuedsuccessfully
```
証明書が発行され、1438時間(約60日)内の更新がスケジュールされました。

ではバックエンドを設定して確認してみましょう。バックエンドにNGINXを立て、exposeします。
```
$ kubectl run nginx --image nginx --port 80
$ kubectl expose deployment nginx --type NodePort
```

Ingressを設定します。ファイル名はingress-nginx-sample.yamlとします。
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
    - host: www.example.com
      http:
        paths:
          - path: /
            backend:
              serviceName: nginx
              servicePort: 80
  tls:
    - hosts:
      - www.example.com
      secretName: prod-example-com-tls
```

デプロイします。
```
$ kubectl apply -f ingress-nginx-sample.yaml
```

いざ確認。
```
$ curl https://www.example.com/
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
[snip]
```

便利ですね。Let's Encryptをはじめ、関連プロジェクトに感謝です。