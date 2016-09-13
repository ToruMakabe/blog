+++
Categories = ["Azure"]
Tags = ["Azure", "Functions"]
date = "2016-09-13T17:30:00+09:00"
title = "Azure Functionsで運用管理サーバレス生活(使用量データ取得編)"

+++

## 背景と動機
Azure Functions使ってますか。「サーバレス」という、ネーミングに突っ込みたい衝動を抑えられないカテゴリに属するため損をしている気もしますが、システムのつくり方を変える可能性がある、潜在能力高めなヤツです。キャッチアップして損はないです。

さて、Azure Functionsを使ってAzureの使用量データを取得、蓄積したいというリクエスト最近いくつかいただきました。いい機会なのでまとめておきます。以下、その背景。

* 運用管理業務がビジネスの差別化要素であるユーザは少ない。可能な限り省力化したい。運用管理ソフトの導入維持はもちろん、その土台になるサーバの導入、維持は真っ先に無くしたいオーバヘッド。もうパッチ当てとか監視システムの監視とか、やりたくない。
* Azure自身が持つ運用管理の機能が充実し、また、運用管理SaaS([MS OMS](https://www.microsoft.com/ja-jp/server-cloud/products-operations-management-suite.aspx)、New Relic、Datadogなど)が魅力的になっており、使い始めている。いつかは運用管理サーバを無くしたい。
* でも、それら標準的なサービスでカバーされていない、ちょっとした機能が欲しいことがある。
* Azureリソースの使用量データ取得が一例。Azureでは使用量データを[ポータルからダウンロード](https://azure.microsoft.com/ja-jp/documentation/articles/billing-understand-your-bill/)したり、[Power BIで分析](https://powerbi.microsoft.com/ja-jp/documentation/powerbi-content-pack-azure-enterprise/)できたりするが、元データは自分でコントロールできるようためておきたい。もちろん手作業なし、自動で。
* ちょっとしたコードを気軽に動かせる仕組みがあるなら、使いたい。インフラエンジニアがさくっと書くレベルで。
* それAzure Functionsで出来るよ。

## 方針
* Azure FunctionsのTimer Triggerを使って、日次で実行
* Azure Resource Usage APIを使って使用量を取得し、ファイルに書き込み
* Nodeで書く (C#のサンプルはたくさんあるので)
* 業務、チームでの運用を考慮して、ブラウザでコード書かずにソース管理ツールと繋げる (Githubを使う)

## Quick Start

### 準備
* ところでAzure Funtionsって何よ、って人はまず[いい資料1](https://blogs.technet.microsoft.com/azure-sa-members/azurefunctions/)と[いい資料2](https://buchizo.wordpress.com/2016/06/04/azure-functions-overview-and-under-the-hood/)でざっと把握を
* AzureのAPIにプログラムからアクセスするため、サービスプリンシパルを作成 ([ここ](https://doc.co/66mYfB)とか[ここ](https://azure.microsoft.com/ja-jp/documentation/articles/resource-group-authenticate-service-principal/)を参考に)
  * 後ほど環境変数に設定するので、Domain(Tenant ID)、Client ID(App ID)、Client Secret(Password)、Subscription IDを控えておいてください
  * 権限はsubscriptionに対するreaderが妥当でしょう
* Githubのリポジトリを作成 (VSTSやBitbucketも使えます)
* 使用量データを貯めるストレージアカウントを作成
  * 後ほど環境変数に設定するので、接続文字列を控えておいてください

### デプロイ
* Function Appを作成
  * ポータル左上"+新規" -> Web + モバイル -> Function App
  * アプリ名は.azurewebsites.net空間でユニークになるように
  * App Seriviceプランは、占有型の"クラシック"か、共有で実行した分課金の"動的"かを選べます。今回の使い方だと動的がお得でしょう
  * メモリは128MBあれば十分です
  * 他のパラメータはお好みで
* 環境変数の設定
  * Function Appへポータルからアクセス -> Function Appの設定 -> アプリケーション設定の構成 -> アプリ設定
  * 先ほど控えた環境変数を設定します(CLIENT_ID、DOMAIN、APPLICATION_SECRET、AZURE_SUBSCRIPTION_ID、azfuncpoc_STORAGE)
* サンプルコードを取得
  * githubに置いてますので、作業するマシンにcloneしてください -> [AZFuncTimerTriggerSample](https://github.com/ToruMakabe/AZFuncTimerTriggerSample)
* 準備済みのGithubリポジトリにpush
* リポジトリとFunction Appを同期
  * Function Appへポータルからアクセス -> Function Appの設定 -> 継続的インテグレーションの構成 -> セットアップ
  * Githubリポジトリとブランチを設定し、同期を待ちます
* Nodeのモジュールをインストール
  * Function Appへポータルからアクセス -> Function Appの設定 -> kuduに移動 -> site/wwwroot/getUsageData へ移動
  * このディレクトリが、実行する関数、functionの単位です
  * "npm install" を実行 (package.jsonの定義に従ってNodeのモジュールが”node_modules"へインストールされます)

これで、指定ストレージアカウントの"usagedata"コンテナに日次で使用量データファイルができます。

## コード解説
3つのファイルをデプロイしました。簡単な順に、ざっと解説します。[コード](https://github.com/ToruMakabe/AZFuncTimerTriggerSample)を眺めながら読み進めてください。

### package.json
主となるコードファイルは後述の"index.js"ですが、その動作に必要な環境を定義します。依存モジュールのバージョンの違いでトラブらないよう、dependenciesで指定するところがクライマックスです。

### function.json
Azure Functionsの特徴である、TriggerとBindingsを定義します。サンプルはTimer Triggerなので、実行タイミングをここに書きます。"schedule"属性に、cron形式({秒}{分}{時}{日}{月}{曜日})で。

"0 0 0 * * *" と指定しているので、毎日0時0分0秒に起動します。UTCです。

### index.js
メインロジックです。

* 先ほど設定した環境変数は、"process.env.HOGE"を通じ実行時に読み込まれます。認証関連情報はハードコードせず、このやり口で。
* 日付関連処理はUTCの明示を徹底しています。Azure Functions実行環境はUTCですが、ローカルでのテストなど他環境を考えると、指定できるところはしておくのがおすすめです。これはクラウドでグローバル展開する可能性があるコードすべてに言えます。
* 0時に起動しますが、使用量データ作成遅延の可能性があるので、処理対象は2日前です。お好みで調整してください。詳細仕様は[こちら](https://msdn.microsoft.com/en-us/library/azure/mt219001.aspx)。
* module.export からが主フローです。asyncを使って、Blobコンテナの作成、使用量データ取得&ファイル書き込みを、順次処理しています。後ほど豆知識で補足します。
* 最後にcontext.done()でFunctionsに対してアプリの終了を伝えます。黙って終わるような行儀の悪い子は嫌いです。
* ヘルパー関数たちは最後にまとめてあります。ポイントはcontinuationTokenを使ったループ処理です。
  * Resource Usage API は、レスポンスで返すデータが多い場合に、途中で切って「次はこのトークンで続きからアクセスしてちょ」という動きをします。
  * ループが2周目に入った場合は、データを書きだすファイルが分かれます。フォーマットは"YYYY-MM-DD_n.json"です。

## 豆知識 (Node on Azure Functions)
* 通信やI/Oの関数など、非同期処理の拾い忘れ、突き抜けに注意してください
  * NodeはJavascript、シングルスレッドなので時間のかかる処理でブロックしないのが基本です
  * Azure FunctionsはNode v6.4.0が使えるのでES6のpromiseが書けるのですが、SDKがまだpromiseを[サポートしていない](https://github.com/Azure/azure-sdk-for-node/issues/1450)ので、サポートされるまではcallbackで堅く書きましょう
* Nodeに限った話ではないですが、Azure Functions Timer TriggerはInput/Output Bindingと組み合わせられません
  * [サポートマトリックス](https://azure.microsoft.com/ja-jp/documentation/articles/functions-reference/#-7)を確認しましょう
  * なのでサンプルではOutput Binding使わずに書きました
  * Input/Outputを使える他のTriggerでは、楽なのでぜひ活用してください

## 豆知識 (Azure Billing API)
* Resource Usage APIは使用量のためのAPIなので、料金に紐づけたい場合は、[Ratecard API](https://azure.microsoft.com/ja-jp/documentation/articles/billing-usage-rate-card-overview/)を組み合わせてください



**それでは、幸せな運用管理サーバレス生活を。**