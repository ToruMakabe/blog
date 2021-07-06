+++
Categories = ["Azure"]
Tags = ["Azure","Functions","ACI"]
date = "2021-07-05T14:00:00+09:00"
title = "Azure Container Instancesの定期実行をAzure Functionsのタイマートリガーで行うパターン"

+++

## 何の話か

ACI(Azure Container Instances)の定期実行を、Azure Functionsのタイマートリガーを使って行う場合、いくつか設計、実装上の考慮点があります。そこで、実装例とともにまとめておきます。

{{< figure src="https://raw.githubusercontent.com/ToruMakabe/Images/master/aci-runner.png?raw=true" width="800">}}

サンプルコードはGitHubに公開しているので、合わせて参照してください。Pythonで書きました。

> [ACI Runner on Azure Functions](https://github.com/ToruMakabe/az-func-aci-runner)

## 背景

以前、ACIの定期実行をGitHub Actionsで行う記事を書きました。

> [Goで書いたAzureのハウスキーピングアプリをContainer InstancesとGitHub Actionsで定期実行する](https://torumakabe.github.io/post/servicetag-checker/)

その後、同様のご相談をいくつかいただきました。ACIの定期実行は、ニーズがあるのでしょう。

アプリの定期実行であればAzure Functionsのタイマートリガー関数という手もあります。それでもACIが選ばれる理由としてよく耳にするのは、「これから作るアプリはできる限りコンテナー化したい」「Functionsでもコンテナーは動かせるが、コンテナーの実行環境としてはFunctionsよりシンプルなACIがいい」です。App Service/Functionsの習熟度も、判断に影響するでしょう。いずれにせよ、実現手段が選択できるのは、良いことだと思います。

ところで、ACIを定期的に走らせるランナーの実装にははいくつかパターンがあります。前述の通りGitHub ActionsなどAzure外部のスケジューラを使う他に、Logic AppsなどAzureのサービスを使う手があります。

> [Azure Logic Apps で自動化された定期的なタスク、プロセス、ワークフローのスケジュールを設定して実行する](https://docs.microsoft.com/ja-jp/azure/logic-apps/concepts-schedule-automated-recurring-tasks-workflows)

> [Azure Logic Apps を使用して Azure Container Instances をデプロイおよび管理する](https://docs.microsoft.com/ja-jp/azure/connectors/connectors-create-api-container-instances)

昨今、Logic Appsのようなローコード環境が注目されています。いっぽう、可能な限りコードで表現、維持したいというニーズも多いです。そこで、Azure Functionsのタイマートリガー関数でランナーを書くならどうする、というのが、この記事の背景です。

## 考慮点

作るのは難しくありません。ですが、設計や実装にあたって、いくつかの考慮点があります。

### Functionsのホスティングオプションと言語ランタイム

1日1回、数十秒で終わるジョブなど、ランナーの実行回数が少なく、短時間で終了するケースもあるでしょう。その場合、コストを考えると、Functionsのプランは従量課金を使いたいものです。従量課金プランの適用可否の判断材料となりがちなVNet統合も、非データプレーンアプリであるACIランナーの用途では不要、と判断できる案件が多いのではないでしょうか。また、オフラインバッチならコールドスタートも問題にならないでしょう。

> [Azure Functions のホスティング オプション](https://docs.microsoft.com/ja-jp/azure/azure-functions/functions-scale)

従量課金プランをターゲットにすると、次はOSと言語ランタイムの選択です。従量課金プランを選択する場合、カスタムコンテナーは利用できないため、言語ランタイムは提供されているものの中から選択する必要があります。選択肢の中から、開発、運用主体の習熟度やチームの意志で決定してください。

冒頭で紹介した、わたしの作ったサンプルはLinux/Pythonです。わたしの周辺、半径10mくらいの意見で決めました。

Windowsの場合には、HTTPトリガーの例ではありますが、PowerShellでのチュートリアルが公開されています。参考にしてください。

> [チュートリアル:HTTP によってトリガーされる Azure Functions を使用してコンテナー グループを作成する](https://docs.microsoft.com/ja-jp/azure/container-instances/container-instances-tutorial-azure-function-trigger)

### ロジックと構成、パラメータの分離

ACIのコンテナーグループを作成、実行するロジックはシンプルです。

* コンテナーグループを実行するリソースグループの存在を確認する
* コンテナーグループが存在する場合、状態を確認する
  * 前回実行が正常に終了したか、などの判断
  * 毎回作り直す場合、存在すれば削除
* コンテナーグループの作成、実行

ですが、この処理に必要な構成情報、パラメータは数多くあります。たとえば、コンテナーグループの create/upgare APIを見ると分かるでしょう。

> [Container Groups - Create Or Update](https://docs.microsoft.com/en-us/rest/api/container-instances/container-groups/create-or-update)

タイマートリガーの場合は、他トリガーのように入力からのパラメータ収集ができません。コードに既定値を書いたり、構成ファイル、環境変数やKey Vaultから集めてくる必要があります。すると、パラメータ収集処理が、コードのかなりの部分を占めてしまいます。

よって、パラメータ収集処理はコンテナーグループ作成ロジックと分離したほうが良いでしょう。

サンプルでは、[タイマートリガー関数](https://github.com/ToruMakabe/az-func-aci-runner/tree/main/app/TimerTrigger)から[パラメータ作成モジュール](https://github.com/ToruMakabe/az-func-aci-runner/tree/main/app/shared)を分離しています。後からランナーを他のジョブでも使いたくなった際、パラメータ、組み合わせが大きく違っても、タイマートリガー関数をできるだけ触らず、パラメータ作成モジュールの変更で済ませようという魂胆です。

### パラメータごとの上書き

それぞれのパラメータを定義する方法はひとつに絞れず、変更可能性やチームでの共有要否、機密度に応じて渡し方を変えたくなりがちです。また、何でもかんでも環境変数で渡してしまうと、Functionsのapp seetingsが散らかってしまいます。そこで、複数のパラメータ設定方式を組み合わせられると、幸せになれます。

* 必須パラメータを減らすため、典型的なパラメータはコードに既定値を埋め込みたい
* ファイルに構成を書いてチームメンバで共有、バージョン管理したい (構成ファイル)
* 実行時に環境に合わせて渡したい (環境変数)
* シークレットストアから渡したい (Key Vault)

なのでサンプルでは、[Python Decouple](https://github.com/henriquebastos/python-decouple/)を使って、パラメータ個別に上書きできるようにしています。リストの下に行くほど強いです。たとえば、コンテナーのリスタートポリシーの既定値は"Never"と[コーディング](https://github.com/ToruMakabe/az-func-aci-runner/blob/main/app/shared/settings.py)していますが、[settings.ini](https://github.com/ToruMakabe/az-func-aci-runner/blob/main/app/shared/settings.ini)で"OnFailure"へと上書きできます。

なおKey Vaultから取得するシークレットに関してはPython Decoupleだけでは上書きできないため、個別に条件を書いています。
