+++
Categories = ["Terraform"]
Tags = ["Terraform", "Azure", "Kubernetes"]
date = "2019-04-26T18:00:00+09:00"
title = "作りかけのAKSクラスターにTerraformで追いプロビジョニングする"

+++

## 何の話か

CLIやポータルで作ったAKSクラスターに、後からIstioなどの基盤ソフトや運用関連のツールを後から入れるのが面倒なので、Terraformを使って楽に入れよう、という話です。アプリのデプロイメントとは分けられる話なので、触れません。

## 動機

Azure CLIやポータルを使えば、AKSクラスターを楽に作れます。加えてAzure Monitorとの連携など、多くのユーザーが必要とする機能は、作成時にオプションで導入できます。

ですが、実際にAKSクラスターを運用するなら、他にも導入したいインフラ関連の基盤ソフトやツールが出てきます。たとえばわたしは最近、クラスターを作る度に後追いでこんなものを入れています。

* Istio
* Kured (ノードOSに再起動が必要なパッチが当たった時、ローリング再起動してくれる)
* HelmのTiller (helm initで作ると守りが緩いので、localhostに限定したdeploymentで入れたい)
* AKSマスターコンポーネントのログ転送設定 (Azure Diagnostics)
* リアルタイムコンテナーログ表示設定

kubectlやAzure CLIでコツコツ設定すると、まあ、めんどくさいわけです。クラスター作成時にAzure CLIやポータルで入れてくれたらなぁ、と思わなくもないですが、これらがみなに必要かという疑問ですし、多くを飲み込もうと欲張ると肥大化します。Kubernetesエコシステムは新陳代謝が激しいので、現状の提供機能は妥当かな、と感じます。

とはいえクラスターを作るたびの追加作業量が無視できないので、わたしはTerraformをよく使います。Azure、Kubernetesリソースを同じツールで扱えるからです。環境をまるっと作成、廃棄できて、とても便利。[今年のはじめに書いた本](https://www.amazon.co.jp/dp/B07L94XGPY)でも、Terraformの活用例を紹介しています。サンプルコードは[こちら](https://github.com/ToruMakabe/Understanding-K8s)。

で、ここまでは、Terraform Azure Providerが、使いたいAKSの機能をサポートしていれば、の話。ここからがこのエントリーの本題です。

AKSはインパクトの大きな機能を、プレビューというかたちで順次提供しています。プレビュー期間にユーザーとともに実績を積み、GAに持っていきます。たとえば2019/4時点で、下記のプレビューが提供されています。

* [Virtual Node](https://docs.microsoft.com/ja-jp/azure/aks/virtual-nodes-cli)
* [Cluster Autoscaler (on Virtual Machine Scale Sets)](https://docs.microsoft.com/ja-jp/azure/aks/cluster-autoscaler)
* [Network Policy (with Calico)](https://docs.microsoft.com/ja-jp/azure/aks/use-network-policies)
* [Pod Security Policy](https://docs.microsoft.com/ja-jp/azure/aks/use-pod-security-policies)
* [Multi Nodepool](https://docs.microsoft.com/en-us/cli/azure/ext/aks-preview/aks/nodepool?view=azure-cli-latest)
* [リアルタイムコンテナーログ表示](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-live-logs)

これらの機能に、すぐにTerraformが対応するとは限りません。たいてい、遅れてやってきます。ということは、使うなら二択です。

1. Terraformの対応を待つ、貢献する
2. Azure CLIやポータルでプレビュー機能を有効化したクラスターを作り、Terraformで追いプロビジョニングする

インパクトの大きい機能は、その価値やリスクを見極めるため、早めに検証に着手したいものです。早めに着手すれば、要否を判断したり運用に組み込む時間を確保しやすいでしょう。そしてその時、本番に近い環境を楽に作れるようにしておけば、幸せになれます。

ということで前置きが長くなりましたが、2が今回やりたいことです。本番のクラスター運用、というよりは、検証環境のセットアップを楽に、という話です。

## 意外に知られていない Terraform Data Source

Terraformを使い始めるとすぐにその存在に気付くのですが、使う前には気付きにくいものがいくつかあります。その代表例がData Sourceです。ざっくりいうと、参照用のリソースです。

Terraformはリソースを"API Management Resource(resource)"として定義すると、作成から廃棄まで、ライフサイクル全体の面倒をみます。つまりresourceとして定義したものをapplyすれば作成し、destroyすれば廃棄します。いっぽうでData Source(data)は参照用ですので、定義したリソースに、変更を加えません。

たとえば、AKSマスターコンポーネントのログをLog Analyticsへ転送するために、Azure Diagnoticsリソースを作成するとしましょう。作成には、対象となる既存AKSクラスターのIDとLog AnalyticsのWorkspace IDが要ります。IDとは、

```
/subscriptions/hogehoge/resourcegroups/fugafuga/providers/Microsoft.ContainerService/managedClusters/hogefuga
```

とかいうやつです。いちいち調べるの、めんどくさい。

そこで、AKSクラスターとLog AnalyticsのWorkspaceをdataとして定義します。

```
data "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.aks_cluster_name}"
  resource_group_name = "${var.aks_cluster_rg}"
}

data "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.la_workspace_name_for_aks}"
  resource_group_name = "${var.la_workspace_rg_for_aks}"
}
```

次のように定義すれば、resource作成時に参照できます。

```
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag_aks"
  target_resource_id         = "${data.azurerm_kubernetes_cluster.aks.id}"
  log_analytics_workspace_id = "${data.azurerm_log_analytics_workspace.aks.id}"

  log {
    category = "kube-apiserver"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
}
```

また、Kubernetesを操作するProvider登録時に、認証情報を渡すこともできます。

```
provider "kubernetes" {
  load_config_file       = false
  host                   = "${data.azurerm_kubernetes_cluster.aks.kube_config.0.host}"
  client_certificate     = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
}
```

こうしておけば、TerraformがKubernetesを操作できます。以下はkured用のサービスアカウントを定義する例です。

```
resource "kubernetes_service_account" "kured" {
  metadata {
    name      = "kured"
    namespace = "kube-system"
  }
}
```

なお、Terraform実行ホスト上のKubernetes configファイルを使って[認証する](https://www.terraform.io/docs/providers/kubernetes/guides/getting-started.html)こともできます。要件に合わせて選択しましょう。

ここまでを、まとめます。Azure CLIやポータルを使って作ったAKSクラスターに対し、TerraformのData SourceやKubenetesのconfigファイルを使って属性、認証情報を取得し、追加プロビジョニングを一括で、楽にできる、という話でした。

## サンプル

ではどんなことができるのか、サンプルをGistに置いておきました。

[サンプルコード](https://gist.github.com/ToruMakabe/46ac0b31f7f8a07fa9a1254f862bc15c)

冒頭で挙げた、以下リソースの導入や設定ができます。

* Istio
* Kured
* HelmのTiller
* AKSマスターコンポーネントのログ転送設定
* リアルタイムコンテナーログ表示設定

HelmとIstioは開発の流れが速いので、ワークアラウンド多めです。詳細はソース上のコメントを参考にしてください。

### 使い方

* Gist上の3ファイルを同じディレクトリに置く
* variables.tf.sampleの変数を設定し、ファイルをリネーム(.sampleを消し、.tfにする)
* Terraform導入済みのホストで実行
  * WSL(Ubuntu 18.04)とmasOS Mojaveで動作検証しています
  * Terraformの設定から確認したい場合は以下を参考に
    * [VM などのインフラストラクチャを Azure にプロビジョニングするための Terraform のインストールと構成](https://docs.microsoft.com/ja-jp/azure/virtual-machines/linux/terraform-install-configure)
    * [Getting started with Terraform using the Azure provider](https://learn.hashicorp.com/terraform/?track=azure#azure)


誰かのお役に、立ちますように。