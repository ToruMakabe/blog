+++
Categories = ["Azure"]
Tags = ["Docker for Windows", "Azure CLI"]
date = "2017-02-28T08:00:30+09:00"
title = "Docker for WindowsでインストールレスAzure CLI 2.0環境を作る"

+++

## Azure CLI 2.0版です
[Docker for WindowsでインストールレスAzure CLI環境を作る](http://torumakabe.github.io/post/dockerforwin_azurecli/)、のAzure CLI 2.0版です。Azure CLI 2.0の一般提供開始に合わせて書いています。

## 動機
* Docker for Windows、もっと活用しようぜ
* がんがんアップデートされるAzure CLI2.0をいちいちインストールしたくない、コンテナ引っ張って以上、にしたい
* 開発端末の環境を汚したくない、いつでもきれいに作り直せるようにしたい
* WindowsでPythonのバージョン管理するのつらくないですか? コンテナで解決しましょう
* ○○レスって言ってみたかった

## やり口
* もちろんDocker for Windows (on Client Hyper-V) を使う
* いちいちdocker run...と打たなくていいよう、エイリアス的にPowerShellのfunction "az_cli" を作る
* "az_cli"入力にてAzure CLIコンテナを起動
* コンテナとホスト(Windows)間でファイル共有、ホスト側のIDEなりエディタを使えるようにする

## 作業の中身
* Docker for Windowsを[インストール](https://docs.docker.com/docker-for-windows/install/)
    * 64bit Windows 10 Pro/Enterprise/Education 1511以降に対応
    * Hyper-Vの有効化を忘れずに
    * Hyper-VとぶつかるVirtualBoxとはお別れです
    * モードをLinuxにします。タスクトレイのdockerアイコンを右クリック [Switch to Linux containers]
    * ドライブ共有をお忘れなく。 タスクトレイのdockerアイコンを右クリック [settings] > [Shared Drives]
* PowerShell functionを作成
    * のちほど詳しく

## PowerShellのfunctionを作る
ここが作業のハイライト。

PowerShellのプロファイルを編集します。ところでエディタはなんでもいいのですが、AzureやDockerをがっつり触る人にはVS Codeがおすすめです。[Azure Resource Manager Template](https://marketplace.visualstudio.com/items?itemName=msazurermtools.azurerm-vscode-tools)や[Docker](https://marketplace.visualstudio.com/items?itemName=PeterJausovec.vscode-docker)むけextensionがあります。

```
PS C:\Workspace\ARM> code $profile
```

こんなfunctionを作ります。

```
function az_cli {
   C:\PROGRA~1\Docker\Docker\Resources\bin\docker.exe run -it --rm -v ${HOME}/.azure:/root/.azure -v ${PWD}:/data -w /data azuresdk/azure-cli-python
}
```

* エイリアスでなくfunctionにした理由は、引数です。エイリアスだと引数を渡せないので
* コンテナが溜まるのがいやなので、--rmで都度消します
* 毎度 az login しなくていいよう、トークンが保管されるコンテナの/root/azureディレクトリをホストの${HOME}/.azureと-v オプションで共有します
* ARM TemplateのJSONファイルなど、ホストからファイルを渡したいため、カレントディレクトリ ${PWD} をコンテナと -v オプションで共有します
* コンテナはdocker hubのazuresdk/azure-cli-pythonリポジトリ、latestを引っ張ります。latestで不具合あればバージョン指定してください

ではテスト。まずはホスト側のファイルを確認。

```
PS C:\Workspace\ARM> ls


    ディレクトリ: C:\Workspace\ARM


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-a----       2017/02/28      8:29           4515 azuredeploy.json
-a----       2017/02/28      8:30            374 azuredeploy.parameters.json
```

いくつかのファイルがあります。

コンテナを起動してみましょう。az_cli functionを呼びます。

```
PS C:\Workspace\ARM> az_cli
bash-4.3#
```

コンテナを起動し、入出力をつなぎました。ここからは頭と手をLinuxに切り替えてください。Azure CLI 2.0コンテナは[alpine linux](https://hub.docker.com/r/azuresdk/azure-cli-python/~/dockerfile/)ベースです。

カレントディレクトリを確認。

```
bash-4.3# pwd
/data
```

ファイル共有できているか確認。

```
bash-4.3# ls
azuredeploy.json             azuredeploy.parameters.json
```

できてますね。

azコマンドが打てるか確認。

```
bash-4.3# az --version
azure-cli (2.0.0+dev)

acr (0.1.1b4+dev)
acs (2.0.0+dev)
appservice (0.1.1b5+dev)
batch (0.1.1b4+dev)
cloud (2.0.0+dev)
component (2.0.0+dev)
configure (2.0.0+dev)
container (0.1.1b4+dev)
core (2.0.0+dev)
documentdb (0.1.1b2+dev)
feedback (2.0.0+dev)
iot (0.1.1b3+dev)
keyvault (0.1.1b5+dev)
network (2.0.0+dev)
nspkg (2.0.0+dev)
profile (2.0.0+dev)
redis (0.1.1b3+dev)
resource (2.0.0+dev)
role (2.0.0+dev)
sql (0.1.1b5+dev)
storage (2.0.0+dev)
taskhelp (0.1.1b3+dev)
vm (2.0.0+dev)

Python (Linux) 3.5.2 (default, Dec 27 2016, 21:33:11)
[GCC 5.3.0]
```

タブで補完も効きます。

```
bash-4.3# az a
account     acr         acs         ad          appservice
```

しあわせ。
