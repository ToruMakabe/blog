+++
Categories = ["Kubernetes"]
Tags = ["Kubernetes", "Azure"]
date = "2019-06-01T09:00:00+09:00"
title = "Kubernetes DeschedulerでPodを再配置する"

+++

## 何の話か

KubernetesのSchedulerはPodをNodeに配置しますが、配置後に見直しを行いません。Nodeの追加や障害からの復帰後など、再配置したいケースはよくあります。Deschedulerはポリシーに合ったPodをNodeから退出させる機能で、SchedulerがPodを再配置する契機を作ります。Incubatorプロジェクトなのですが、もっと知られてもいいと思ったのでこの記事を書いています。

機能をイメージしやすいよう、実際の動きを伝えるのがこの記事の目的です。Azure Kubernetes Serviceでの実行結果を紹介しますが、他のKubernetesでも同様に動くでしょう。

## Deschedulerとは

[@ponde_m](https://twitter.com/ponde_m) さんの資料がとても分かりやすいので、おすすめです。この記事を書こうと思ったきっかけでもあります。

>[図で理解する Descheduler](https://speakerdeck.com/daikurosawa/introduction-to-descheduler)

これを読んでからプロジェクトのREADMEに進むと理解が進むでしょう。

>[Descheduler for Kubernetes](https://github.com/kubernetes-incubator/descheduler/tree/master)

OpenShiftはDeschedulerをPreview Featureとして提供しているので、こちらも参考になります。

>[Descheduling](https://docs.openshift.com/container-platform/3.11/admin_guide/scheduling/descheduler.html)

## 動きを見てみよう

実行した環境はAzure Kubernetes Serviceですが、特に環境依存する要素は見当たらないので、他のKubernetesでも動くでしょう。

Deschedulerは、Nodeの数が少ないクラスターで特に有効です。Nodeの数が少ないと、偏りも大きくなるからです。

例えばこんなシナリオです。あるある。

* 諸事情から2Nodeで運用を開始
* 知らずにか忘れてか、レプリカ数3のDeploymentを作る
* 当たり前だけど片方のNodeに2Pod寄ってる
* Node追加
* Podは寄りっぱなし 残念

Nodeの障害から復帰後も、同様の寄りっぱなし問題が起こります。

では、このシナリオで動きを追ってみましょう。

### 事前準備

DeschedulerをKubernetesのJobとして動かしてみます。Deschedulerはプロジェクト公式のイメージを提供していないようなので、[プロジェクトのREADME](https://github.com/kubernetes-incubator/descheduler#running-descheduler-as-a-job-inside-of-a-pod)を参考に、イメージをビルドしてレジストリにプッシュしておきます。以降はAzure Container Registryにプッシュしたとして手順を進めます。

### NodeにPodを寄せる

はじめのNode数は2です。

```
$ kubectl get nodes
NAME                            STATUS   ROLES   AGE   VERSION
aks-pool1-27450415-vmss000000   Ready    agent   34m   v1.13.5
aks-pool1-27450415-vmss000001   Ready    agent   34m   v1.13.5
```

レプリカ数3で、NGINXのDeploymentを作ります。nginx.yamlとします。

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: ３
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            cpu: 500m
```

デプロイします。

```
$ kubectl apply -f nginx.yaml
```

aks-pool1-27450415-vmss000000に寄ってますね。

```
$ kubectl get po -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP            NODE                            NOMINATED NODE   READINESS GATES
nginx-6d4df4db7b-cqrkl   1/1     Running   0          12s   10.240.0.42   aks-pool1-27450415-vmss000001   <none>           <none>
nginx-6d4df4db7b-dg267   1/1     Running   0          12s   10.240.0.22   aks-pool1-27450415-vmss000000   <none>           <none>
nginx-6d4df4db7b-kxmml   1/1     Running   0          12s   10.240.0.11   aks-pool1-27450415-vmss000000   <none>           <none>
```

### Nodeを追加する

Nodeを追加し、3Nodeにします。以下はマルチノードプール構成クラスター向けのコマンドです。シングルノードプール構成のクラスターでは、[こちら](https://docs.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-scale)を参考に。

```
$ az aks nodepool scale -g oreno-rg --cluster-name oreno-cls -n pool1 --node-count 3

$ kubectl get nodes
NAME                            STATUS   ROLES   AGE   VERSION
aks-pool1-27450415-vmss000000   Ready    agent   38m   v1.13.5
aks-pool1-27450415-vmss000001   Ready    agent   38m   v1.13.5
aks-pool1-27450415-vmss000003   Ready    agent   68s   v1.13.5
```

aks-pool1-27450415-vmss000003が追加されました。余談ですが、この検証の前にNodeを増やしたり減らしたりしてるので000002が飛んで採番されています。気にせず。

ではPodの様子を見てみましょう。

```
$ kubectl get po -o wide
NAME                     READY   STATUS    RESTARTS   AGE     IP            NODE                            NOMINATED NODE   READINESS GATES
nginx-6d4df4db7b-cqrkl   1/1     Running   0          5m39s   10.240.0.42   aks-pool1-27450415-vmss000001   <none>           <none>
nginx-6d4df4db7b-dg267   1/1     Running   0          5m39s   10.240.0.22   aks-pool1-27450415-vmss000000   <none>           <none>
nginx-6d4df4db7b-kxmml   1/1     Running   0          5m39s   10.240.0.11   aks-pool1-27450415-vmss000000   <none>           <none>
```

Nodeを増やしたのに、寄りっぱなしですね。

### Descheduler用のリソースを作る

それではDeschedulerを作る準備を。手順は今後変化すると思うので、試す場合は都度[プロジェクトのREADME](https://github.com/kubernetes-incubator/descheduler/tree/master)を確認してください。

わたしはDescheduler動かすのに必要なリソースを、descheduler.yamlにまとめています。

```
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: descheduler-cluster-role
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "watch", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list", "delete"]
- apiGroups: [""]
  resources: ["pods/eviction"]
  verbs: ["create"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: descheduler-sa
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: descheduler-cluster-role-binding
subjects:
- kind: ServiceAccount
  name: descheduler-sa
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: descheduler-cluster-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
data:
  policy.yaml: |
    apiVersion: "descheduler/v1alpha1"
    kind: "DeschedulerPolicy"
    strategies:
      "RemoveDuplicates":
         enabled: true
      "RemovePodsViolatingInterPodAntiAffinity":
         enabled: true
      "LowNodeUtilization":
         enabled: true
         params:
           nodeResourceUtilizationThresholds:
             thresholds:
               "cpu" : 20
               "memory": 20
               "pods": 20
             targetThresholds:
               "cpu" : 50
               "memory": 50
               "pods": 50
kind: ConfigMap
metadata:
  name: descheduler-policy-configmap
  namespace: kube-system
```

Dechedulerのポリシーは、プロジェクトページのexamplesに[あるもののまま](https://github.com/kubernetes-incubator/descheduler/blob/master/examples/policy.yaml)としました。先ほど用意したクラスターでは、aks-pool1-27450415-vmss000000にレプリカが2つ寄っているので、RemoveDuplicatesが適用されると期待できます。

では作ります。

```
$ kubectl apply -f descheduler.yaml
```

### Descheduler Jobを実行

descheduler-job.yamlとします。imageの確認をお忘れなく。

```
apiVersion: batch/v1
kind: Job
metadata:
  name: descheduler-job
  namespace: kube-system
spec:
  parallelism: 1
  completions: 1
  template:
    metadata:
      name: descheduler-pod
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ""
    spec:
        containers:
        - name: descheduler
          image: oreno.azurecr.io/descheduler:0.9.0
          volumeMounts:
          - mountPath: /policy-dir
            name: policy-volume
          command: ["/bin/descheduler",  "--policy-config-file", "/policy-dir/policy.yaml"]
        restartPolicy: "Never"
        serviceAccountName: descheduler-sa
        volumes:
        - name: policy-volume
          configMap:
            name: descheduler-policy-configmap
```

いざ実行。

```
$ kubectl apply -f descheduler-job.yaml
$ kubectl get jobs.batch -n kube-system
NAME              COMPLETIONS   DURATION   AGE
descheduler-job   1/1           9s         11s
```

さて、偏りは解消したでしょうか。

```
$ kubectl get po -o wide
NAME                     READY   STATUS    RESTARTS   AGE     IP            NODE                            NOMINATED NODE   READINESS GATES
nginx-6d4df4db7b-cqrkl   1/1     Running   0          15m     10.240.0.42   aks-pool1-27450415-vmss000001   <none>           <none>
nginx-6d4df4db7b-dg267   1/1     Running   0          15m     10.240.0.22   aks-pool1-27450415-vmss000000   <none>           <none>
nginx-6d4df4db7b-w7mb6   1/1     Running   0          7m33s   10.240.0.87   aks-pool1-27450415-vmss000003   <none>           <none>
```

aks-pool1-27450415-vmss000000にあった1つのPodが退出され、新たにaks-pool1-27450415-vmss000003で作成されたことがわかります。

## Deschedulerプロジェクトの現状

このようにDeschedulerは、特に少ないNode數で偏りが大きくなりがちなクラスターでとても有用です。ですが、アクティブなメンテナーの数が少なく、現時点では積極的にKubernetesのコア機能を目指す感じではなさそうです。

>[What is the current status of this project?](https://github.com/kubernetes-incubator/descheduler/issues/138)

>[Which version of kuberenetes will have this project included?](https://github.com/kubernetes-incubator/descheduler/issues/152)

アドオンとして使ってもとても便利で感謝ではありますが、コア機能に、というかたはぜひ応援、貢献しましょう。
