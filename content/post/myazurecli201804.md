+++
Categories = ["Azure"]
Tags = ["Azure", "Terraform"]
date = "2018-04-09T15:00:00+09:00"
title = "俺のAzure CLI 2018春版"

+++

## 春の環境リフレッシュ祭り
最近KubernetesのCLI、kubectlを使う機会が多いのですが、なかなかイケてるんですよ。かゆい所に手が届く感じ。そこで、いい機会なのでAzure CLIまわりも最新の機能やツールで整えようか、というのが今回の動機。気づかないうちに、界隈が充実していた。

## 俺のおすすめ 3選

* デフォルト設定
  * リソースグループやロケーション、出力形式などのデフォルト設定ができる
* エイリアス
  * サブコマンドにエイリアスを付けられる
  * 引数付きの込み入った表現もできる
* VS Code プラグイン
  * [Azure CLI Toolsプラグイン](https://marketplace.visualstudio.com/items?itemName=ms-vscode.azurecli) でazコマンドの編集をコードアシストしてくれる
  * 編集画面上でコマンド選択して実行できる

## デフォルト設定
$AZURE_CONFIG_DIR/configファイルで構成設定ができます。$AZURE_CONFIG_DIR の既定値は、Linux/macOS の場合$HOME/.azure、Windowsは%USERPROFILE%\.azure。

[Azure CLI 2.0 の構成](https://docs.microsoft.com/ja-jp/cli/azure/azure-cli-configuration?view=azure-cli-latest)

まず変えたいところは、コマンドの出力形式。デフォルトはJSON。わたしのお気持ちは、普段はTable形式、掘りたい時だけJSON。なのでデフォルトをtableに変えます。

```
[core]
output = table
```

~~そしてデフォルトのリソースグループを設定します。以前は「デフォルト設定すると、気づかないところで事故るから、やらない」という主義だったのですが、Kubernetesのdefault namespaceの扱いを見て「ああ、これもありかなぁ」と改宗したところ。~~
軽く事故ったので、リソースグループのデフォルト設定をいまはやめています。デフォルトのご利用は計画的に。

```
[defaults]
group = default-ejp-rg
```

他にもロケーションやストレージアカウントなどを設定できます。ロケーションはリソースグループの属性を継承させたい、もしくは明示したい場合が多いので、設定していません。

ということで、急ぎUbuntuの仮想マシンが欲しいぜという場合、az vm createコマンドの必須パラメーター、-gと-lを省略できるようになったので、さくっと以下のコマンドでできるようになりました。

デフォルト指定したリソースグループを、任意のロケーションに作ってある前提です。

```
az vm create -n yoursmplvm01 --image UbuntuLTS
```

## エイリアス
$AZURE_CONFIG_DIR/aliasにエイリアスを書けます。

[Azure CLI 2.0 のエイリアス拡張機能](https://docs.microsoft.com/ja-jp/cli/azure/azure-cli-extension-alias?view=azure-cli-latest)

前提はAzure CLI v2.0.28以降です。以下のコマンドでエイリアス拡張を導入できます。現時点ではプレビュー扱いなのでご注意を。

```
az extension add --name alias
```

ひとまずわたしは以下3カテゴリのエイリアスを登録しました。

### 頻繁に打つからできる限り短くしたい系

```
[ls]
command = list

[nw]
command = network

[pip]
command = public-ip

[fa]
command = functionapp
```

例えばデフォルトリソースグループでパブリックIP公開してるか確認したいな、と思った時は、az network public-ip listじゃなくて、こう打てます。

```
$ az nw pip ls
Name                  ResourceGroup    Location    Zones    AddressVersion    AllocationMethod      IdleTimeoutInMinutes
ProvisioningState
--------------------  ---------------  ----------  -------  ----------------  ------------------  ----------------------
-------------------
yoursmplvm01PublicIP  default-ejp-rg   japaneast            IPv4              Dynamic                                  4
Succeeded
```

### クエリー打つのがめんどくさい系
VMに紐づいてるパブリックIPを確認したいときは、こんなエイリアス。

```
[get-vm-pip]
command = vm list-ip-addresses --query [].virtualMachine.network.publicIpAddresses[].ipAddress
```

実行すると。

```
$ az get-vm-pip -n yoursmplvm01
Result
-------------
52.185.133.68
```

### 引数を確認するのがめんどくさい系
リソースグループを消したくないけど、中身だけ消したいってケース、よくありますよね。そんなエイリアスも作りました。--template-uriで指定しているGistには、空っぽのAzure Resource Manager デプロイメントテンプレートが置いてあります。このuriをいちいち確認するのがめんどくさいので、エイリアスに。

```
[empty-rg]
command = group deployment create --mode Complete --template-uri https://gist.githubusercontent.com/ToruMakabe/28ad5177a6de525866027961aa33b1e7/raw/9b455bfc9608c637e1980d9286b7f77e76a5c74b/azuredeploy_empty.json
```

以下のコマンドを打つだけで、リソースグループの中身をバッサリ消せます。投げっぱなしでさっさとPC閉じて帰りたいときは --no-waitオプションを。

```
$ az empty-rg
```

[位置引数](https://docs.microsoft.com/ja-jp/cli/azure/azure-cli-extension-alias?view=azure-cli-latest#create-an-alias-command-with-arguments)や[Jinja2テンプレート](https://docs.microsoft.com/ja-jp/cli/azure/azure-cli-extension-alias?view=azure-cli-latest#process-arguments-using-jinja2-templates)を使ったエイリアスも作れるので、込み入ったブツを、という人は挑戦してみてください。

## VS Code プラグイン (Azure CLI Tools )
Azure CLIのVS Code向けプラグインがあります。コードアシストと編集画面からの実行が2大機能。紹介ページのGifアニメを見るのが分かりやすいです。

[Azure CLI Tools](https://marketplace.visualstudio.com/items?itemName=ms-vscode.azurecli)

プラグインを入れて、拡張子.azcliでファイルを作ればプラグインが効きます。長いコマンドを補完支援付きでコーディングしたい、スクリプトを各行実行して確認しながら作りたい、なんて場合におすすめです。

## 注意点

* エイリアスには補完が効かない
  * bashでのCLI実行、VS Code Azure CLI Toolsともに、現時点(2018/4)でエイリアスには補完が効きません
* ソースコード管理に不要なファイルを含めない
  * $AZURE_CONFIG_DIR/ 下には、aliasやconfigの他に、認証トークンやプロファイルといったシークレット情報が置かれます。なのでGitなどでソースコード管理する場合は、aliasとconfig以外は除外したほうがいいでしょう