+++
Categories = ["Windows"]
Tags = ["Windows", "Boxstarter", "Automation"]
date = "2017-10-13T14:30:00+09:00"
title = "自動化を愛するWindows使いへ Boxstarterのすすめ"

+++

## Windowsのセットアップどうする問題
そろそろFall Creators Updateが来ますね。これを機にクリーンインストールしようかという人も多いのはないでしょうか。端末って使っているうちに汚れていく宿命なので、わたしは定期的に「こうあるべき」という状態に戻します。年に2～３回はスッキリしたい派なので、アップデートはいいタイミングです。

でもクリーンインストールすると、設定やアプリケーションの導入をGUIでやり直すのが、すこぶるめんどくせぇわけです。自動化したいですね。そこでBoxstarterをおすすめします。便利なのに、意外に知られていない。

[Boxstarter](http://boxstarter.org/)

わたしはマイクロソフトの仲間、Jessieの[ポスト](https://blog.jessfraz.com/post/windows-for-linux-nerds/)で知りました。サンクスJessie。

## Boxstarterで出来ること

* シンプルなスクリプトで
  * Windowsの各種設定
  * Chocolateyパッケージの導入
* 設定ファイルをネットワーク経由で読み込める
  * Gistから
* ベアメタルでも仮想マシンでもOK

## 実行手順
手順は[Boxstarterのサイト](http://boxstarter.org/Learn/WebLauncher)で紹介されています。

* スクリプトを作る
* Gistに上げる
* Boxstarterを導入する

PowerShell 3以降であれば
```
. { iwr -useb http://boxstarter.org/bootstrapper.ps1 } | iex; get-boxstarter -Force
```

* Gist上のスクリプトを指定して実行する

なお2017/10/13時点で、Boxstarterサイトのサンプルにはtypoがあるので注意 (-PackageNameオプション)
```
Install-BoxstarterPackage -PackageName "https://gist.githubusercontent.com/ToruMakabe/976ceab239ec930f8651cfd72087afac/raw/4fc77a1d08f078869962ae82233b2f8abc32d31f/boxstarter.txt" -DisableReboots
```

以上。

## サンプル設定ファイル
設定ファイルは[こんな感じ](https://gist.github.com/ToruMakabe/976ceab239ec930f8651cfd72087afac)に書きます。

ちなみに、わたしの環境です。こまごまとした設定やツールの導入はもちろん、Hyper-Vやコンテナ、Windows Subsystem for Linuxの導入も、一気にやっつけます。

```
# Learn more: http://boxstarter.org/Learn/WebLauncher

# Chocolateyパッケージがないもの、パッケージ更新が遅いものは別途入れます。メモです。
# Install manually (Ubuntu, VS, snip, Azure CLI/PS/Storage Explorer, Terraform, Go, 1Password 6, Driver Management Tool)

#---- TEMPORARY ---
Disable-UAC

#--- Fonts ---
choco install inconsolata
  
#--- Windows Settings ---
# 可能な設定はここで確認 --> [Boxstarter WinConfig Features](http://boxstarter.org/WinConfig)
Disable-GameBarTips

Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowFileExtensions
Set-TaskbarOptions -Size Small -Dock Bottom -Combine Full -Lock

Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneShowAllFolders -Value 1

#--- Windows Subsystems/Features ---
choco install Microsoft-Hyper-V-All -source windowsFeatures
choco install Microsoft-Windows-Subsystem-Linux -source windowsfeatures
choco install containers -source windowsfeatures

#--- Tools ---
choco install git.install
choco install yarn
choco install sysinternals
choco install 7zip

#--- Apps ---
choco install googlechrome
choco install docker-for-windows
choco install microsoft-teams
choco install slack
choco install putty
choco install visualstudiocode

#--- Restore Temporary Settings ---
Enable-UAC
Enable-MicrosoftUpdate
Install-WindowsUpdate -acceptEula
```

便利。

ちなみにわたしはドキュメント類はOneDrive、コードはプライベートGit/GitHub、エディタの設定はVisual Studio/Visual Studio Code [Settings Sync拡張](https://marketplace.visualstudio.com/items?itemName=Shan.code-settings-sync)を使っているので、Boxstarterと合わせ、 環境の再現は2～3時間もあればできます。最近、バックアップからのリストアとか、してないです。

新しい端末の追加もすぐできるので、物欲が捗るという副作用もあります。