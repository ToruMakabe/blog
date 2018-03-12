+++
Categories = ["Azure"]
Tags = ["Azure", "AKS", "Kubernetes", "DNS"]
date = "2018-03-12T00:21:00+09:00"
title = "AKSのService作成時にホスト名を付ける"

+++

## 2つのやり口
Azure Container Service(AKS)はServiceを公開する際、パブリックIPを割り当てられます。でもIPだけじゃなく、ホスト名も同時に差し出して欲しいケースがありますよね。

わたしの知る限り、2つの方法があります。

* AKS(k8s) 1.9で対応した[DNSラベル名付与機能](https://github.com/kubernetes/kubernetes/pull/47849)を使う
* [Kubenetes ExternalDNS](https://github.com/kubernetes-incubator/external-dns)を使ってAzure DNSへAレコードを追加する

以下、AKS 1.9.2での実現手順です。

## DNSラベル名付与機能
簡単です。Serviceのannotationsに定義するだけ。試しにnginxをServiceとして公開し、確認してみましょう。

[nginx-label.yaml]
```
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: nginx
spec:
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx
        name: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: hogeginx
  annotations:
    service.beta.kubernetes.io/azure-dns-label-name: hogeginx
spec:
  selector:
    app: nginx
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

デプロイ。
```
$ kubectl create -f nginx-label.yaml
```

パブリックIP(EXTERNAL-IP)が割り当てられた後、ラベル名が使えます。ルールは [ラベル名].[リージョン].cloudapp.azure.com です。
```
$ curl hogeginx.eastus.cloudapp.azure.com
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
[snip]
```

ドメイン名は指定しなくていいから、Service毎にホスト名を固定したいんじゃ、という場合にはこれでOK。

## Kubenetes ExternalDNS
任意のドメイン名を使いたい場合は、Incubatorプロジェクトのひとつ、Kubenetes ExternalDNSを使ってAzure DNSへAレコードを追加する手があります。本家の説明は[こちら](https://github.com/kubernetes-incubator/external-dns/blob/master/docs/tutorials/azure.md)。

Kubenetes ExternalDNSは、Azure DNSなどAPIを持つDNSサービスを操作するアプリです。k8sのDeploymentとして動かせます。Route 53などにも対応。

さて動かしてみましょう。前提として、すでにAzure DNSにゾーンがあるものとします。

ExternalDNSがDNSゾーンを操作できるよう、サービスプリンシパルを作成しましょう。スコープはDNSゾーンが置かれているリソースグループ、ロールはContributorとします。
```
$ az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/your-subscription-id/resourceGroups/hoge-dns-rg" -n hogeExtDnsSp
```

appId、password、tenantを控えておいてください。次でsecretに使います。

ではExteralDNSに渡すsecretを作ります。まずJSONファイルに書きます。

[azure.json]
```
{
    "tenantId": "your-tenant",
    "subscriptionId": "your-subscription-id",
    "aadClientId": "your-appId",
    "aadClientSecret": "your-password",
    "resourceGroup": "hoge-dns-rg"
}
```

JSONファイルを元に、secretを作ります。
```
$ kubectl create secret generic azure-config-file --from-file=azure.json
```

ExteralDNSのマニフェストを作ります。ドメイン名はexmaple.comとしていますが、使うDNSゾーンに合わせてください。以下はRBACを使っていない環境での書き方です。

[extdns.yaml]
```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: external-dns
spec:
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      containers:
      - name: external-dns
        image: registry.opensource.zalan.do/teapot/external-dns:v0.4.8
        args:
        - --source=service
        - --domain-filter=example.com # (optional) limit to only example.com domains; change to match the zone created above.
        - --provider=azure
        - --azure-resource-group=hoge-dns-rg # (optional) use the DNS zones from the tutorial's resource group
        volumeMounts:
        - name: azure-config-file
          mountPath: /etc/kubernetes
          readOnly: true
      volumes:
      - name: azure-config-file
        secret:
          secretName: azure-config-file
```

ExternalDNSをデプロイします。
```
$ kubectl create -f extdns.yaml
```

ではホスト名を付与するServiceのマニフェストを作りましょう。先ほどのDNSラベル名付与機能と同様、annotationsへ定義します。

[nginx-extdns.yaml]
```
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: nginx-extdns
spec:
  template:
    metadata:
      labels:
        app: nginx-extdns
    spec:
      containers:
      - image: nginx
        name: nginx
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: hogeginx-extdns
  annotations:
    external-dns.alpha.kubernetes.io/hostname: hogeginx.example.com
spec:
  selector:
    app: nginx-extdns
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

デプローイ。
```
$ kubectl create -f nginx-extdns.yaml
```

パブリックIP(EXTERNAL-IP)が割り当てられた後、Aレコードが登録されます。確認してみましょう。
```
$ az network dns record-set a list -g hoge-dns-rg -z example.com -o table
Name      ResourceGroup       Ttl  Type    Metadata
--------  ----------------  -----  ------  ----------
hogeginx  hoge-dns-rg         300  A
```

ゲッツ。
```
$ curl hogeginx.example.com
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
[snip]
```

Incubatorプロジェクトなので今後大きく変化する可能性がありますが、ご参考になれば。