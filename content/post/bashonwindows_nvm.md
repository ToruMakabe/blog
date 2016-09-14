+++
Categories = ["Node"]
Tags = ["Node", "Bash", "Windows"]
date = "2016-09-14T15:00:00+09:00"
title = "Bash on WindowsでNode開発環境を作る"

+++

## Bash on Windows 現時点での使いどころ
Windows 10 Anniversary Updateでベータ提供がはじまったBash on Ubuntu on Windows、みなさん使ってますか。わたしは、まだベータなので本気運用ではないのですが、開発ツールを動かすのに使い始めてます。Linux/Macと同じツールが使えるってのは便利です。

たとえばNodeのバージョン管理。Windowsには[nodist](https://github.com/marcelklehr/nodist)がありますが、Linux/Macでは動きません。Linux/Macで使ってる[NVM](https://github.com/creationix/nvm)がWindowsで動いたら、いくつもバージョン管理ツールを覚えずに済むのに！あ、Bash on Windowsあるよ！！おお、そうだな！！！という話です。

最近、Azure FunctionsでNode v6.4.0が[使えるようになった](https://blogs.msdn.microsoft.com/appserviceteam/2016/09/01/azure-functions-0-5-release-august-portal-update/)ので、「これからバージョン管理どうすっかな」と考えていた人も多いのでは。それはわたしです。

## NVMのインストール
* Bash on Ubuntu on Windowsを入れます ([参考](http://www.atmarkit.co.jp/ait/articles/1608/08/news039.html))
* Bash on Ubuntu on Windowsを起動します
* build-essentialとlibssl-devを入れます

```
sudo apt-get install build-essential checkinstall
sudo apt-get install libssl-dev
```

* インストールスクリプトを流します

```
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.31.7/install.sh | bash
```

バージョンアップを考慮し、インストールのつど[公式ページ](https://github.com/creationix/nvm)を確認してください。

以上。

## NVMの使い方
```
nvm install 6.4.0
```
指定のバージョンをインストールします。

```
nvm use 6.4.0
```
使うバージョンを指定します。

簡単ですね。

```
cd /mnt/c/your_work_directory
node ./index.js
```
なんて感じで、書いたコードをテストしちゃってください。

なお、Visual Studio Code使いの人は[統合ターミナルをBashにしておく](https://blogs.msdn.microsoft.com/ayatokura/2016/08/06/vsc_windows_bash/)と、さらに幸せになれます。
