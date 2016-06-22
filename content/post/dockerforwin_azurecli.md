+++
Categories = ["Azure"]
Tags = ["Docker for Windows", "Azure CLI"]
date = "2016-06-22T15:00:00+09:00"
title = "Docker for WindowsでインストールレスAzure CLI環境を作る"

+++

## 舌の根の乾かぬ内に
[最近](http://torumakabe.github.io/post/azure_osstools_iac/)、VagrantとVirualBoxで似たようなやり口を紹介しましたが、気にしないでください。テクノロジーの進化は早い。

## 動機
* Docker for Windows(on Client Hyper-V)のベータが一般開放された
* Dockerもそうだが、Hyper-V前提のツールが今後増えそう、となると、それとぶつかるVirtualBoxをぼちぼちやめたい
* 月一ペースでアップデートされるAzure CLIをいちいちインストールしたくない、コンテナ引っ張って以上、にしたい
* 作業端末の環境を汚したくない、いつでもきれいに作り直せるようにしたい
* ○○レスって言ってみたかった

## やり口
* Docker for Windows (on Client Hyper-V)
* いちいちdocker run...と打たなくていいよう、エイリアス的にPowerShellのfunction "azure_cli" を作る
* "azure_cli"入力にてAzure CLIコンテナを起動
* コンテナとホスト(Windows)間でファイル共有、ホスト側のIDEなりエディタを使えるようにする

## 作業の中身
* Docker for Windowsを[インストール](https://docs.docker.com/docker-for-windows/)
    * 64bit Windows 10 Pro/Enterprise/Education 1511以降に対応
    * Hyper-Vの有効化を忘れずに
    * Hyper-VとぶつかるVirtualBoxとはお別れです
    * Docker for Windowsの起動時にIPをとれないケースがありますが、その場合はsettings -> Network から、設定変えずにApplyしてみてください。いまのところこれで対処できています。この辺はベータなので今後の調整を期待しましょう。
* PowerShell functionを作成
    * のちほど詳しく

## PowerShellのfunctionを作る
ここが作業のハイライト。

PowerShellのプロファイルを編集します。ところでエディタはなんでもいいのですが、AzureやDockerをがっつり触る人にはVS Codeがおすすめです。[Azure Resource manager Template](https://marketplace.visualstudio.com/items?itemName=msazurermtools.azurerm-vscode-tools)や[Docker](https://marketplace.visualstudio.com/items?itemName=PeterJausovec.vscode-docker)むけextensionがあります。

```
PS C:\Workspace\dockereval\arm> code $profile
```

こんなfunctionを作ります。

```
function azure_cli {
   C:\PROGRA~1\Docker\Docker\Resources\bin\docker.exe run -it --rm -v ${HOME}/.azure:/root/.azure -v ${PWD}:/data -w /data microsoft/azure-cli:latest
}
```

* エイリアスでなくfunctionにした理由は、引数です。エイリアスだと引数を渡せないので
* コンテナが溜まるのがいやなので、--rmで都度消します
* 毎度 azure login しなくていいよう、トークンをホストの${HOME}/.azureに保管し、コンテナと -v オプションで共有します
* ARM TemplateのJSONファイルなど、ホストからファイルを渡したいため、カレントディレクトリ ${PWD} をコンテナと -v オプションで共有します
* コンテナはdocker hubのMicrosoft公式イメージ、latestを引っ張ります。latestで不具合あればバージョン指定してください

ではテスト。まずはホスト側のファイルを確認。

```
PS C:\Workspace\dockereval\arm> ls


    ディレクトリ: C:\Workspace\dockereval\arm


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
d-----       2016/06/22     11:21                subd
-a----       2016/06/22     10:26           8783 azuredeploy.json
-a----       2016/06/22     11:28            690 azuredeploy.parameters.json
```

いくつかのファイルとサブディレクトリがあります。

コンテナを起動してみましょう。azure_cli functionを呼びます。

```
PS C:\Workspace\dockereval\arm> azure_cli
root@be41d3389a21:/data#
```

コンテナを起動し、入出力をつなぎました。

ファイル共有できているか確認。

```
root@be41d3389a21:/data# ls
azuredeploy.json  azuredeploy.parameters.json  subd
```

できてますね。

azureコマンドが打てるか確認。

```
root@be41d3389a21:/data# azure -v
0.10.1
```

しあわせ。