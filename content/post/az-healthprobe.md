+++
Categories = ["Azure"]
Tags = ["Azure","Github","Go"]
date = "2021-04-02T11:20:00+09:00"
title = "Azure Application Insightsのカスタム可用性テストを使って プライベートネットワーク対応の可用性テストプローブをGoで書く"

+++

## 何の話か

以下のサンプル(C# & Azure Functions)と同じことをGoでやりたいね、という相談をいただき、やってみた話です。

> [Azure Functions を使用してカスタム可用性テストを作成して実行する](https://docs.microsoft.com/ja-jp/azure/azure-monitor/app/availability-azure-functions)

## 背景

ユーザ視点でサービス、サイトの可用性を客観的に把握できている、外形監視しているケースは、意外に少なかったりします。明らかにしてしまうといろいろ問題が、という裏事情はさておき、サービスレベル維持、改善のためには客観的な根拠があったほうがいいでしょう。

Azure Application Insightsには[可用性テスト](https://docs.microsoft.com/ja-jp/azure/azure-monitor/app/monitor-web-app-availability)や[SLAレポート](https://docs.microsoft.com/ja-jp/azure/azure-monitor/app/sla-report)機能があり、視覚化や分析、レポート作成をサクッと実現できます。

なのですが、この可用性テストのプローブがインターネット上に配置されているため、監視対象もインターネットに口を開いている必要があります。Azureの仮想ネットワークなど、プライベートネットワークにあるサイト向けには使えません。

ああ残念、と思いきや、手はあります。Application Insightsは可用性テスト結果を受け取るAPIを公開しているので、そこにデータを送るカスタムプローブを作って、プライベートネットワークに配置すれば、実現できます。

そんな背景があり、公開されているのが[前述のサンプル](https://docs.microsoft.com/ja-jp/azure/azure-monitor/app/availability-azure-functions)です。C#とFunctions使いであればこれでOK。このエントリはGoなど他言語での実装に関心がある人向けです。

## 作ったもの

Goで書いたプローブのコードと、環境構築、デプロイに使うTerraform、GitHub Actionsのコードは公開してありますので、詳しくは[そちら](https://github.com/ToruMakabe/az-healthprobe-go)を。

{{< figure src="https://raw.githubusercontent.com/ToruMakabe/Images/master/healthprobe.jpg?raw=true" width="500">}}

* Goが動いて監視対象とApplication Insights APIエンドポイントにアクセスできる環境であればOK
* 可搬性を考慮し、プローブはDockerコンテナにしました
* このサンプルではプローブをAzure Container Instancesで動かします
* GitHubから監視対象のリスト(csv)をクローン、コンテナにマウントします
* [リスト](https://github.com/ToruMakabe/az-healthprobe-go/blob/main/conf/sample_target_mnt_private.csv)には監視対称名、監視URL、間隔(秒)を書きます
* 監視対象の可用性が閾値を下回った場合と、プローブから可用性テスト結果が送られてこない場合に、アラートアクションを実行します

## 考えたことメモ

作りながら考えたことが参考になるかもしれないので、残しておきます。

* Goでもカスタムハンドラを使えば、Azure Functionsで似たようなことができます。でもこのユースケースでAzure Container Instanceを選んだ理由は以下です。
  * コスト。Azure Functionsで仮想ネットワーク統合ができるプランと比較すると安い。プローブのためだけだと、Functionsは過剰か。他の用途ですでにApp Serviceプランがあって相乗りできるなら、ありかも。
  * 配布イメージが軽量。Functionsでデプロイ方式にコンテナを選んだ場合、Function Hostをコンテナイメージに含める必要があり、サイズが大きくなる。圧縮しても300MBを超える。Functionsで実装するなら、コンテナにしない手を選んだかもしれない。
  * トリガーとバインドが不要。プローブの実行契機がタイマーなので、Functionsの持つ豊富なイベントトリガーが不要。監視対象ごとにタイマー設定するなら、リストを読み込んでアプリのロジックでやったほうが楽。入出力バインドも要らない。
  * シンプル。カスタムハンドラを書かなくていいので。カスタムハンドラ、難しくはないですが。
* Application Insightsのメトリックアラートは[即時性に欠ける](https://azure.microsoft.com/ja-jp/support/legal/sla/application-insights/v1_0/)ことを考慮しましょう。
  * Application Insightsに送られたテレメトリがメトリックアラートに利用できるようになるまで準備時間が必要なので、即時性が必要な場合には可用性テストだけに頼らず、サービス側のAzure Monitorメトリックアラートを組み合わせましょう。
