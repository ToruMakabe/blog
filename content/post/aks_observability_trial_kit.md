+++
Categories = ["Kubernetes"]
Tags = ["Kubernetes", "Azure"]
date = "2019-06-26T18:30:00+09:00"
title = "Azure Kubernetes ServiceのObservabilityお試しキットを作った"

+++

## 何の話か

Observabilityって言いたかっただけではありません。Azure Kubernetes Service(AKS)の監視について相談されることが多くなってきたので、まるっと試せるTerraform HCLとサンプルアプリを作りました。

[Gistに置いたHCL](https://gist.github.com/ToruMakabe/916d4329f6e92c3fda1c8d6440afd47b#file-main-tf)で、以下のような環境を作れます。

![Overview](https://raw.githubusercontent.com/ToruMakabe/Images/master/aks-observability-overview.png?raw=true "Overview")

## 動機

監視とは、ビジネスとそれを支える仕組みがどのような状態かを把握し、判断や行動につなげるものです。そして何を監視し、何をもって健全、危険と判断するかは、人や組織によります。安易にベストプラクティスを求めるものではないでしょう。

とはいえ、コンテナー技術が本格的に普及し始めたのは最近ですし、手を動かしていない段階では、議論が発散しがちです。そこでお試しキットを作りました。AKSクラスターとサンプルアプリケーション、それらを監視するサービスとツールをまるっと試せます。

このお試しキットは、Azureの提供するサービスとオープンソースのツールのみでまとめました。ですが、世にはいい感じのKubernetes対応ツールやサービスが多くあります。このキットであたりをつけてから、他も探ってみてください。

## 視点

クラウド、コンテナー、サーバーレスの監視という文脈で、可観測性(Observability)という言葉を目にすることが多くなりました。オブザーバビブベボ、いまだに口が回りません。

制御理論用語である可観測性がITの世界で使われるようになった理由は、諸説あるようです。監視を行為とすると、可観測性は性質です。「監視対象側に、状態を把握しやすくする仕組みを備えよう」というニュアンスを感じませんか。後付けではなく、監視をあらかじめ考慮したうえでアプリや基盤を作ろう、ということだと捉えています。いわゆるバズワードかもしれませんが、監視を考え直すいいきっかけになりそうで、わたしは好意的です。

お試しキットは、3つの要素と2つの配置を意識して作りました。

### メトリクス、ロギング、トレーシング

可観測性の3大要素はメトリクス、ロギング、トレーシングです。お試しキットのサービスやツールがどれにあたるかは、つど説明します。

### 外からか、内からか

Kubernetesに限りませんが「監視主体」と「監視対象」の分離は重要な検討ポイントです。監視するものと監視されるものを同じ基盤にのせると、不具合があった時、どちらがおかしくなっているかを判断できない場合があります。できれば分離して、独立性を持たせたい。

いっぽう、監視対象の内側に仕組みを入れることで、外からは取りづらい情報を取得できたりします。外からの監視と内からの監視は排他ではないので、組み合わせるのがいいでしょう。

## お試しキットの使い方

### 前提条件

* Terraform 0.12
* Bash (WSL Ubuntu 18.04とmacOS 10.14.5で検証しています)
* Azure CLI
* kubectl
* Helm 2.13.1 (2.14は[この問題](https://github.com/helm/helm/issues/5806)にて保留中)
* AKS診断ログ機能の[有効化](https://docs.microsoft.com/ja-jp/azure/aks/view-master-logs#enable-diagnostics-logs)
  * 「注意」に記載された az feature register コマンドで機能フラグを有効する作業のみでOK
  * Log Analyticsへの送信設定は不要です (Terraformで行います)

### 実行手順

Gistに置いた[variables.tf](https://gist.github.com/ToruMakabe/916d4329f6e92c3fda1c8d6440afd47b#file-variables-tf)を好みの値で編集し、[main.tf](https://gist.github.com/ToruMakabe/916d4329f6e92c3fda1c8d6440afd47b#file-main-tf)を同じディレクトリに置いて実行(init、plan、apply)してください。

セットアップが完了するとサンプルアプリの公開IP(front_service_ip)とGrafanaの管理者パスワード(grafana_password)が出力されるので、控えておきましょう。

### 補足

* AKSクラスターのノードはVMSSとしていますが、VMSSを有効化していない場合はmain.tfのazurerm_kubernetes_cluster.aks.agent_pool_profile.typeをAvailabilitySetに[変更してください](https://www.terraform.io/docs/providers/azurerm/r/kubernetes_cluster.html#type)
* AKSクラスターのノード構成は Standard_D2s_v3(2vCPU、8GBメモリ) * 3 です
  * main.tfのazurerm_kubernetes_cluster.aks.agent_pool_profile.vm_sizeで定義してますので、必要に応じて変更してください
  * メモリはPrometheusが頑張ると足りなくなりがちなので、ノードあたり8GBは欲しいところです
* 環境を一括作成、削除する作りなので、本番で活用したい場合はライフサイクルを意識してください
  * Log Analyticsのワークスペース作成処理はログ保管用に分ける、など
* 以下の理由でTerraformがコケたら、シンプルに再実行してください
  * Azure ADのレプリケーションに時間がかかった場合 (サービスプリンシパルがない、不正と言われる)
    * azurerm_role_assignment.aks provisionerのsleep時間を長くしたり、サービスプリンシパルを事前に作成しておくことで対処できます
  * Azure CLIの認証情報が期限切れする場合
    * Terraformコミュニティで[対応中](https://github.com/hashicorp/go-azure-helpers/issues/22)です
* HCLが長いですが、後半のほとんどはサンプルアプリのDeploymentです
  * 実際はアプリケーションのDeploymentをTerraformでデリバリーするケースは少ないかと。あくまで今回のサンプル向けです

## 触ってみよう

### メトリクス

まずはメトリクスから。メトリクスとは「状態を数値で表せるもの」です。単数系はメトリック。CPUやメモリの使用率、Kubernetes固有ではNotReady状態のノード数やPendingのポッド数などがそれにあたります。

Kubernetesでどのようなメトリクスに注目すべきかについては、議論が活発です。探せば参考になる情報が数多くあります。"Golden signals"、"RED Method"、"USE Method"で検索すると、いろいろ見つかるでしょう。

お試しキットで作った環境では、Azure Monitorを主役に、Prometheusを組み合わせています。Azure Monitorのコンテナー向け機能は次のページをトップにしたツリーに情報がまとまっていますので、まずざっと読んでおくと理解しやすいです。

> [コンテナーに対する Azure Monitor の概要](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-overview)

#### Azure Monitor メトリック

Azure MonitorはAzureの監視サービス群です。以前は従来からある監視サービスとAzure生まれのサービスがいくつか独立して提供されていたのですが、現在はAzure Monitorの傘の下で機能統合が進んでいます。

Azure Monitorのメトリックは収集、可視化、アラート機能を持ちます。AKSに限らず、様々なAzureサービスのメトリックがサポートされています。

> [Azure Monitor のサポートされるメトリック](https://docs.microsoft.com/ja-jp/azure/azure-monitor/platform/metrics-supported)

AKSでサポートされているメトリクスは以下です。AKSクラスターのマスターからメトリックを収集し、Azure Monitorのメトリックストアに貯めます。

> [Microsoft.ContainerService/managedClusters](https://docs.microsoft.com/ja-jp/azure/azure-monitor/platform/metrics-supported#microsoftcontainerservicemanagedclusters)

ノードの平均CPU、メモリ利用率、ノードやポッドの状態が対象です。種類は多くありませんが、クリティカルなメトリックを取得できます。

お試しキットでは1分おきに"NotReady"、"Unknown"のノードがないか確認し、5分単位でカウントが0より大きければ管理者にメールを通知するように設定しています。疑似的にノード障害を起こすには、ノードをVMレベルで割り当て解除してみてください。メールが飛んできます。メールの他には、WebhookやLogic Appなどが通知手段、通知先として[使えます](https://docs.microsoft.com/ja-jp/azure/azure-monitor/platform/action-groups)。

他のメトリックにもアラートルールを設定したい場合は、こちらを参考に。

[Azure Monitor を使用してメトリック アラートを作成、表示、管理する](https://docs.microsoft.com/ja-jp/azure/azure-monitor/platform/alerts-metric)

AKSだけでなく他Azureサービスと統一できること、AKSと分離して外部から客観的に監視できることがAzure Monitorのメリットです。

#### Prometheus & Grafana

Azure Monitorはクリティカルなメトリック向けにはいいのですが、Kubernetesの健康状態を詳しく把握するにはメトリックの種類が物足りません。そこでよく使う手は、Prometheusとの組み合わせです。AKS上にPrometheusをのせて、メトリック監視を補完します。

お試しキットではPrometheus Operatorを使っています。

> [Prometheus Operator](https://github.com/coreos/prometheus-operator)

メトリクスバックエンドとしてPrometeusを、メトリクス可視化のためにGrafanaを導入し、Kubernetes向けの基本的な設定は済ませています。まずは分かりやすく、Grafanaでメトリクスを見てみましょう。

```
kubectl port-forward -n monitoring svc/prometheus-operator-grafana 3000:80
```

ブラウザでlocalhost:3000にアクセスすると、ポート転送されてGrafanaのログイン画面が出ます。ユーザー名はadmin、パスワードは先ほどTerraformのapply時に出力されたものを使ってください。忘れた場合はterraform outputで再出力できます。

サンプルのKubernetes向けダッシュボードをGrafanaコミュニティサイトからインポートしています。画面左のメニュー "Dashboards"から、 > Manage > smaple と辿って表示してください。

> [Kubernetes Cluster (Prometheus)](https://grafana.com/dashboards/6417)

![Grafana](https://grafana.com/api/dashboards/6417/images/4128/image "Grafana")

また、Prometheus Operatorは導入時に一般的なアラートルールを[設定します](https://github.com/helm/charts/tree/master/stable/prometheus-operator#developing-prometheus-rules-and-grafana-dashboards)。Prometheus上で確認してみましょう。

```
kubectl port-forward -n monitoring svc/prometheus-operator-prometheus 9090:9090
```

localhost:9090からPrometheusのWeb UIを開き、メニューの Alerts で設定済みのルールや状態を見ることができます。ルールにマッチしたアラートは、赤くなっています。

試しにアラートを発生させてみましょう。みんな大嫌いなポッドのCrashLoopBackoffを意図的に起こします。

```
kubectl run --generator=run-pod/v1 phoenix --image=busybox --restart=Always -- /bin/sh -c 'exit 1'
```

すると、以下のルール KubePodCrashLooping にマッチし、アラートがPending状態になります。

```
alert: KubePodCrashLooping
expr: rate(kube_pod_container_status_restarts_total{job="kube-state-metrics"}[15m])
  * 60 * 5 > 0
for: 1h
labels:
  severity: critical
annotations:
  message: Pod {{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }})
    is restarting {{ printf "%.2f" $value }} times / 5 minutes.
  runbook_url: https://github.com/kubernetes-monitoring/kubernetes-mixin/tree/master/runbook.md#alert-name-kubepodcrashlooping
  ```

for、つまり持続時間が1hなので、このルールに1時間マッチし続けると、アラートとして扱われます。Prometheusはアラートの通知機能を分離しており、通知はAlertmanagerが行います。AlertmanagerにもWeb UIがあります。

```
kubectl port-forward -n monitoring svc/prometheus-operator-alertmanager 9093:9093
```

AzureはVMからのメール送信を[制限している](https://docs.microsoft.com/ja-jp/azure/virtual-network/troubleshoot-outbound-smtp-connectivity)ため、お試しキットではPrometheusからの通知設定をしていません。もしWebhook通知などを試してみたい場合は、[こちら](https://prometheus.io/docs/alerting/overview/)を参考にConfigを書いてみてください。Configの投入は環境作成時に使ったTerraforrm HCLに追記してapplyすると楽です。

PrometheusはKubernetesと同じCNCFプロジェクトということもあり、親和性は大きな利点です。エコシステムも魅力で、試す価値はあります。いっぽうでKubernetesクラスター上に導入する場合は、監視主体と対象が同居するため独立性、客観性が懸念です。これは利点とのトレードオフなので、Azure Monitorなど外部からの監視をうまく組み合わせましょう。

### ロギング

#### Azure Monitor for Containers (コンテナー分析)

Azure Monitorのログ分析サービスであるLog Analyticsを活用したソリューションです。KubernetesのDaemonSetとして動くLog Analytics Agentが、アプリケーションコンテナーのログ、Kubernetesのインベントリ情報、性能情報を取得しLog Analyticsワークスペースへ送信します。ワークスペースに蓄積されたデータを使って、様々な可視化や分析を行えます。

機能については、公式ドキュメントが詳しいのでそちらを。

> [コンテナーの Azure Monitor を使用して AKS クラスターのパフォーマンスを把握する](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-analyze)

> [Azure Monitor for containers からログを照会する方法](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-log-search)

お試しキットではLog Analyticsワークスペースの作成、AKSへの紐づけが済んでいます。また、コンテナーからのライブログ表示もできるように設定済みです。いろいろ試してみてください。

> [ログとイベントをリアルタイムで表示する方法 (プレビュー)](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-live-logs)

なお、AKSはKubernetesのマスターコンポーネントをAzureが管理するマネージドサービスで、既定ではKubernetesのAPI ServerやSchedulerなどマスターコンポーネントのログは出力されません。ですが、診断設定を有効化することでストレージに保管したり、Log Analyticsに送ることができます。お試しキットではこれも有効化しています。

> [Azure Kubernetes Service (AKS) での Kubernetes マスター ノード ログの有効化とレビュー](https://docs.microsoft.com/ja-jp/azure/aks/view-master-logs)

Kubernetesのログ分析にはELKスタックが使われることが多いですが、AzureではAzure Monitor for Containersが楽に使えるので、ぜひ一度お試しを。

##### メトリックアラートエンジンとしてのAzure Monitor for Containers

Azure MonitorのLog Analyticsワークスペースに蓄積されたログには、クエリーを書けます。そして定期的にクエリーを実行し、結果が条件にマッチした場合にAzure Moniterのアラート通知機能を呼び出すことができます。Scheduled Queryと呼ばれます。  

> [コンテナー用 Azure Monitor でパフォーマンスの問題に関するアラートを設定する方法](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-alerts)

つまり、ログから特定の文字列を検索し、アラートにするという使い方の他に、メトリックアラート的な使い方もできます。ログからメトリックを動的に作り出すというアイデアです。ログの柔軟性を活かしたやり方と言えます。

ですが、短サイクルで数値を取得、評価する目的で作られているメトリックと異なり、Log Analyticsワークスペースはあくまでログ志向の作りです。向き不向きを考えると、頻繁に測定、評価したい値はメトリックを使うべきでしょう。また、Scheduled Query比較的新しい機能であるため、現時点ではまだAzure CLIやTerraformで設定できず、[ポータルやARMテンプレートでの設定が必要](https://docs.microsoft.com/ja-jp/azure/azure-monitor/platform/alerts-log)という制約もあります。AKSクラスターをインプレースアップグレードせず、毎回新しいクラスターを作って切り替えるという運用では、監視設定を含めて構築を自動化したくなるため、考慮すべき制約です。

メトリックアラート用途では、まずAzure MonitorメトリックアラートかPrometheusアラートを検討し、それでも満たせない場合はScheduled Queryを使う、というのがわたしのスタンスです。

### トレーシング

コンテナーのアプリケーションは変更や更新、スケールの柔軟性を高めるため、ひとつのコンテナーにいくつも機能を詰め込まず、シンプルなコンテナーを組み合わせる設計が好まれます。となると「アプリケーションを構成する一連のコンテナーの、どこが期待通りに動き、どこが遅い/おかしいかを調べたい」というニーズが生まれます。これを実現するコンセプトが分散トレーシングです。

#### Azure Monitor Application Insights

AzureMonitorにはにはApplication Insightsという分散トレーシングを実現するサービスがあり、コンテナーやKubernetesに関係なく使えます。ASP.NET CoreやJava、Nodeなどのフレームワーク、言語むけの[SDK](https://github.com/microsoft/ApplicationInsights-Home)があり、テレメトリをApplication Insightsに送るコードを埋め込みます。

以上、では面白くないので、お試しキットではOpenCensusに対応したサンプルアプリケーションを動かしています。OpenCensusはGoogleがリードする分散トレーシング、メトリック収集の[仕様](https://opencensus.io/)です。マイクロソフトもOpenCensusを[支持しており](https://cloudblogs.microsoft.com/opensource/2018/06/13/microsoft-joins-the-opencensus-project/)、Application InsightsをOpenCensusのバックエンドとして[使えるように取り組んでいます](https://opencensus.io/exporters/supported-exporters/go/applicationinsights/)。

Application InsightsへOpenCensus仕様のテレメトリを送るために、現在は[ローカルフォワーダー](https://docs.microsoft.com/ja-jp/azure/azure-monitor/app/opencensus-local-forwarder)を使います。アプリはOpenCensusのライブラリを使い、ローカルフォワーダーへトレースしたテレメトリを送ります。そしてローカルフォワーダーが変換、バッファリングしてApplication Insightsへ送る、という仕掛けです。

サンプルとして、[シンプルなGoのWebアプリ](https://gist.github.com/ToruMakabe/916d4329f6e92c3fda1c8d6440afd47b#file-main-go)を作りました。DockerfileもGistに[置いておきます](https://gist.github.com/ToruMakabe/916d4329f6e92c3fda1c8d6440afd47b#file-dockerfile)。[公式ドキュメント](https://docs.microsoft.com/ja-jp/azure/azure-monitor/app/opencensus-go)を参考にしたアプリケーションで、ターゲットサービスを環境変数で指定された場合はそれを呼び出し、20ms待ってから応答するようにカスタマイズしています。

では、サンプルアプリケーションの公開エンドポイントへアクセスしてみましょう。IPアドレスはお試しキットを実行した際に控えたfront_service_ipです。terraform outputやkubectl get svcの結果(EXTERNAL-IP)でも確認できます。

何度かアクセスしたのち、Application Insightsのアプリケーションマップを見てみましょう。

![Map](https://raw.githubusercontent.com/ToruMakabe/Images/master/aks-observability-map.png?raw=true "Map")

frontからmiddle、middleからbackを呼びだす、という流れが可視化されています。

また、エンドツーエンドの性能、依存関係も「パフォーマンス」メニューで可視化できます。

![Dependency](https://raw.githubusercontent.com/ToruMakabe/Images/master/aks-observability-dependency.png?raw=true "Dependency")

ところでOpenCensusは、別のトレーシング仕様であるOpenTracingとマージされ、今後[OpenTelemetry](https://opentelemetry.io/)が存続プロジェクトになりました。マイクロソフトからも、OpenCensusに引き続き[支持する](https://cloudblogs.microsoft.com/opensource/2019/05/23/announcing-opentelemetry-cncf-merged-opencensus-opentracing/)とアナウンスが出ています。当面はApplication Insights SDKを使いつつ、OpenTelemetryの本格化を横目でチェックする感じがいいのでは、と思います。

##### Application Insights 可用性テスト

分散トレーシングというよりはメトリックアラートなのですが、Application InsightsにはWeb可用性テスト、という機能もあります。いわゆる外形監視機能です。お試しキットでは設定していませんが、ポータルから試してみてください。

> [Web サイトの可用性と応答性の監視](https://docs.microsoft.com/ja-jp/azure/azure-monitor/app/monitor-web-app-availability)

Terraformでの環境構築中、KubernetesのサービスにIPを割り当てたあと、Webテストを自動設定することもできます。ですがTerraformのWebテストリソースからはまだアラートの設定ができないため、お試しキットでは設定していません。(Terraformの対応後に参考となるよう、アラート設定なしのHCLはコメントとして残しておきました)

#### サービスメッシュは?

Kubernetesを追っている人であれば、分散トレーシング機能はIstioなどのサービスメッシュ側が持つようになる、と考えているかもしれません。実際、Appication InsightsでもIstio向けアダプターが開発されています。

> [Kubernetes でホストされるアプリケーションに対するゼロ インストルメンテーション アプリケーション監視](https://docs.microsoft.com/ja-jp/azure/azure-monitor/app/kubernetes)

とはいえサービスメッシュは進化が激しく、かつService Mesh Interfaceなど標準化の動きもあり、落ち着くにはもう少し時間がかかる印象です。

> [Service Mesh Interface: A standard interface for service meshes on Kubernetes](https://smi-spec.io/)

もしサービスメッシュへの期待が分散トレーシング中心であれば、現時点では無理してサービスメッシュに取り組むよりも、アプリケーションにトレーシングのコードを埋め込む方がいいのではないかと考えます。

## 最後に: お試しキットを超えて

冒頭でも書きましたが、このお試しキットはあくまでひとつの実装例です。Kubernetesの可観測性を高めるサービスやツールは数多いです。DatadogやNew Relicなど、監視に特化したサービスの機能は見るべきものがあります。ぜひ調べてみてください。

特にアラート通知はPagerDutyなど特化したサービスがあるとうれしいと思います。たとえばAzure MonitorとPrometheusから別々のフォーマットや受諾機能を持つシステムからアラートを受け、それぞれ対応するのは若干つらい。アラートをいい感じにまとめてくれる仕組みは、検討する価値があると思います。

ではでは Enjoy Observability
