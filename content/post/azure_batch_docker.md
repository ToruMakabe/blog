+++
Categories = ["Azure"]
Tags = ["Azure", "Docker", "Batch"]
date = "2016-04-29T17:00:00+09:00"
title = "Azure BatchとDockerで管理サーバレスバッチ環境を作る"

+++

## サーバレスって言いたいだけじゃないです
Linux向けAzure BatchのPreviewが[はじまり](https://azure.microsoft.com/ja-jp/blog/announcing-support-of-linux-vm-on-azure-batch-service/)ました。地味ですが、なかなかのポテンシャルです。

クラウドでバッチを走らせる時にチャレンジしたいことの筆頭は「ジョブを走らせる時だけサーバ使う。待機時間は消しておいて、
節約」でしょう。

ですが、仕組み作りが意外に面倒なんですよね。管理サーバを作って、ジョブ管理ソフト入れて、Azure SDK/CLI入れて。クレデンシャルを安全に管理して。可用性確保して。バックアップして。で、管理サーバは消せずに常時起動。なんか中途半端です。

その課題、Azure Batchを使って解決しましょう。レッツ管理サーバレスバッチ処理。

## コンセプト

* 管理サーバを作らない
* Azure Batchコマンドでジョブを投入したら、あとはスケジュール通りに定期実行される
* ジョブ実行サーバ群(Pool)は必要な時に作成され、処理が終わったら削除される
* サーバの迅速な作成とアプリ可搬性担保のため、dockerを使う
* セットアップスクリプト、タスク実行ファイル、アプリ向け入力/出力ファイルはオブジェクトストレージに格納

## サンプル

Githubにソースを[置いておきます](https://github.com/ToruMakabe/Azure_Batch_Sample)。

### バッチアカウントとストレージアカウント、コンテナの作成とアプリ、データの配置

[公式ドキュメント](https://azure.microsoft.com/ja-jp/documentation/articles/batch-technical-overview/)で概要を確認しましょう。うっすら理解できたら、バッチアカウントとストレージアカウントを作成します。

ストレージアカウントに、Blobコンテナを作ります。サンプルの構成は以下の通り。

    .
    ├── blob
    │   ├── application
    │   │   ├── starttask.sh
    │   │   └── task.sh
    │   ├── input
    │   │   └── the_star_spangled_banner.txt
    │   └── output

applicationコンテナに、ジョブ実行サーバ作成時のスクリプト(starttask.sh)と、タスク実行時のスクリプト(task.sh)を配置します。

* [starttask.sh](https://github.com/ToruMakabe/Azure_Batch_Sample/blob/master/blob/application/starttask.sh) - docker engineをインストールします
* [task.sh](https://github.com/ToruMakabe/Azure_Batch_Sample/blob/master/blob/application/task.sh) - docker hubからサンプルアプリが入ったコンテナを持ってきて実行します。[サンプル](https://github.com/ToruMakabe/Azure_Batch_Sample/tree/master/docker)はPythonで書いたシンプルなWord Countアプリです

また、アプリにデータをわたすinputコンテナと、実行結果を書き込むoutputコンテナも作ります。サンプルのinputデータはアメリカ国歌です。

コンテナ、ファイルには、適宜SASを生成しておいてください。inputではreadとlist、outputでは加えてwrite権限を。

さて、いよいよジョブをJSONで定義します。詳細は[公式ドキュメント](https://msdn.microsoft.com/en-us/library/azure/dn820158.aspx?f=255&MSPPError=-2147217396)を確認してください。ポイントだけまとめます。

* 2016/04/29 05:30(UTC)から開始する - schedule/doNotRunUntil
* 4時間ごとに実行する - schedule/recurrenceInterval
* ジョブ実行後にサーバプールを削除する - jobSpecification/poolInfo/autoPoolSpecification/poolLifetimeOption
* ジョブ実行時にtask.shを呼び出す  - jobSpecification/jobManagerTask/commandLine
* サーバはUbuntu 14.04とする - jobSpecification/poolInfo/autoPoolSpecification/virtualMachineConfiguration
* サーバ数は1台とする - jobSpecification/poolInfo/autoPoolSpecification/pool/targetDedicated
* サーバプール作成時にstarttask.shを呼び出す - jobSpecification/poolInfo/autoPoolSpecification/pool/startTask

```    
  {
  "odata.metadata":"https://myaccount.myregion.batch.azure.com/$metadata#jobschedules/@Element",
  "id":"myjobschedule1",
  "schedule": {
    "doNotRunUntil":"2016-04-29T05:30:00.000Z",
    "recurrenceInterval":"PT4H"
  },
  "jobSpecification": {
    "priority":100,
    "constraints": {
      "maxWallClockTime":"PT1H",
      "maxTaskRetryCount":-1
    },
    "jobManagerTask": {
      "id":"mytask1",
      "commandLine":"/bin/bash -c 'export LC_ALL=en_US.UTF-8; ./task.sh'",
      "resourceFiles": [ {
        "blobSource":"yourbloburi&sas",
        "filePath":"task.sh"
      }], 
      "environmentSettings": [ {
        "name":"VAR1",
        "value":"hello"
      } ],
      "constraints": {
        "maxWallClockTime":"PT1H",
        "maxTaskRetryCount":0,
        "retentionTime":"PT1H"
      },
      "killJobOnCompletion":false,
      "runElevated":true,
      "runExclusive":true
      },
      "poolInfo": {
        "autoPoolSpecification": {
          "autoPoolIdPrefix":"mypool",
          "poolLifetimeOption":"job",
          "pool": {
            "vmSize":"STANDARD_D1",
            "virtualMachineConfiguration": {
              "imageReference": {
                "publisher":"Canonical",
                "offer":"UbuntuServer",
                "sku":"14.04.4-LTS",
                "version":"latest"
              },
              "nodeAgentSKUId":"batch.node.ubuntu 14.04"
            },
            "resizeTimeout":"PT15M",
            "targetDedicated":1,
            "maxTasksPerNode":1,
            "taskSchedulingPolicy": {
              "nodeFillType":"Spread"
            },
            "enableAutoScale":false,
            "enableInterNodeCommunication":false,
            "startTask": {
              "commandLine":"/bin/bash -c 'export LC_ALL=en_US.UTF-8; ./starttask.sh'",
              "resourceFiles": [ {
                "blobSource":"yourbloburi&sas",
                "filePath":"starttask.sh"
              } ],
              "environmentSettings": [ {
                "name":"VAR2",
                "value":"Chao"
              } ],
              "runElevated":true,
              "waitForSuccess":true
            },
            "metadata": [ {
              "name":"myproperty",
              "value":"myvalue"
            } ]
          }
        }
      }
    }
  }
```    

そろそろ人類はJSONに変わるやり口を発明すべきですが、XMLよりはいいですね。

それはさておき、面白そうなパラメータたち。並列バッチやジョブリリース時のタスクなど、今回使っていないものもまだまだあります。応用版はまたの機会に。

ではスケジュールジョブをAzure BatchにCLIで送り込みます。

    azure batch job-schedule create -f ./create_jobsched.json -u https://yourendpoint.location.batch.azure.com -a yourbatchaccount -k yourbatchaccountkey
    
以上です。あとはAzureにお任せです。4時間に1回、アメリカ国歌の単語を数える刺身タンポポなジョブですが、コツコツいきましょう。

## Azure Automationとの使い分け
Azure Automationを使っても、ジョブの定期実行はできます。大きな違いは、PowerShellの要否と並列実行フレームワークの有無です。Azure AutomationはPowerShell前提ですが、Azure BatchはPowerShellに馴染みのない人でも使うことができます。また、今回は触れませんでしたが、Azure Batchは並列バッチ、オートスケールなど、バッチ処理に特化した機能を提供していることが特長です。うまく使い分けましょう。
