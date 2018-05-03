+++
Categories = ["WSL"]
Tags = ["WSL", "Golang"]
date = "2018-05-02T17:00:00+09:00"
title = "WSLENVでWSLとWindowsの環境変数を共有する(Go開発環境編)"

+++

## 見た目は地味だが役に立つ
Windows 10 April 2018 Update (別名: バージョン1803)がリリースされました。タイムラインなど目立つ機能が注目されていますが、開発者支援系の機能、ツールも[拡充](https://blogs.msdn.microsoft.com/commandline/2018/03/07/windows10v1803/)されています。特に、WSL/Windowsの連携、相互運用まわりは着実に進化しています。そのうちのひとつが、このエントリーで紹介するWSLENVです。

WSLENVは、WSL/Windows間で環境変数を共有する仕組みです。ただ単純に共有するだけでなく、ルールに従って変換も行います。これが地味に便利。でも地味だから、あまり話題になっていない。なので具体例で紹介しよう、というのがこのエントリーの目的です。

## TL;DR
英語が読めて、「あ、それ便利ね」とピンとくる人は以下を。

[Share Environment Vars between WSL and Windows](https://blogs.msdn.microsoft.com/commandline/2017/12/22/share-environment-vars-between-wsl-and-windows/)

## Go開発環境を例に
前述のリンクでも紹介されていますが、Goの開発環境はWSLENVの代表的なユースケースです。GOPATHをいい感じにWSL/Windowsで共有できます。掘り下げていきましょう。

### 想定開発者像、ペルソナ

* Windows端末を使っている
* Go言語を使っている
* CLIはbash/WSL中心
  * スクリプト書くならPowerShellもいいけど、インタラクティブな操作はbashが楽
  * アプリをDockerコンテナーとしてビルドするなど、OSSエコシステム、ツールとの連携を考慮
* とはいえエディタ/IDEはWindows側で動かしたい、最近はVS Code中心

### 前提条件

* WSL、WindowsそれぞれにGoを導入
  * バージョン管理のためにも、パッケージマネージャーがおすすめ
  * わたしはWSL(Ubuntu)でapt、WindowsではChocolateyを使ってGoを導入しています
* GOPATHは %USERPROFILE%go とする
  * ユーザー名を tomakabeとすると C:\Users\tomakabe\go
  * setx GOPATH "$env:USERPROFILE\go" で設定
  * WSLでもこのディレクトリをGOPATHとする
* VS Code + [Go拡張](https://github.com/Microsoft/vscode-go)をWindowsに導入
* WindowsのCLIはPowerShellを利用

### そぞろ歩き その1(WindowsでのGo開発)
では、何が課題で、WSLがどのようにそれを解決するか、見ていきましょう。

まず、Windowsで環境変数GOPATHを確認します。

```
PS C:\WINDOWS\system32> Get-ChildItem env:GOPATH

Name                           Value
----                           -----
GOPATH                         C:\Users\tomakabe\go
```

GOPATHに移動し、ディレクトリ構造を確認します。この環境にはすでにディレクトリbinとsrcがあり、binにはいくつかexeが入っています。VS CodeのGo拡張を入れると導入を促されるツール群は、ここに格納され、構文チェックや補完でVS Codeと連動します。

```
PS C:\WINDOWS\system32> cd C:\Users\tomakabe\go
PS C:\Users\tomakabe\go> ls


    ディレクトリ: C:\Users\tomakabe\go


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
d-----       2018/05/02     11:10                bin
d-----       2018/05/02     11:06                src

PS C:\Users\tomakabe\go> ls .\bin\


    ディレクトリ: C:\Users\tomakabe\go\bin


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-a----       2018/05/02     11:10       14835200 dlv.exe
-a----       2018/05/02     11:09        4239360 go-outline.exe
-a----       2018/05/02     11:09        4045824 go-symbols.exe
-a----       2018/05/02     11:08       11094528 gocode.exe
-a----       2018/05/02     11:09        5708288 godef.exe
[snip]
```

サンプルコードのディレクトリへ移動し、中身を確認します。シンプルな挨拶アプリです。

```
PS C:\Users\tomakabe\go> cd .\src\github.com\ToruMakabe\work\
PS C:\Users\tomakabe\go\src\github.com\ToruMakabe\work> cat .\hello.go
package main

import "fmt"

func main() {
        fmt.Println("Hello Go on the new WSL")
}
```

ビルドして動かしてみましょう。Windows環境ではデフォルトで実行ファイルとしてexeが作られます。

```
PS C:\Users\tomakabe\go\src\github.com\ToruMakabe\work> go build .\hello.go
PS C:\Users\tomakabe\go\src\github.com\ToruMakabe\work> ls


    ディレクトリ: C:\Users\tomakabe\go\src\github.com\ToruMakabe\work


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
-a----       2018/05/02     11:54        2049536 hello.exe
-a----       2018/05/02     11:10             91 hello.go


PS C:\Users\tomakabe\go\src\github.com\ToruMakabe\work> .\hello.exe
Hello Go on the new WSL
```

ここまでは従来のWindowsにおけるGo開発環境です。ではWSLに話を移しましょう。

### そぞろ歩き その2(WSLでのGo開発)
WSLにつなぎます。ターミナルは任意ですが、わたしはVS Codeの統合ターミナルが好きです。コードを書きながら操作できるので。

GOPATHを確認します。空っぽです。WSLは既定でWindowsへ環境変数PATHを渡します。PATHは特別扱いです。ですが、他の環境変数は、指定しないと渡しません。よってWindowsで設定していても、WSLから見るとGOPATHは空っぽです。

```
~ $ echo $GOPATH

```

$HOMEもきれいな状態です。
```
~ $ ls
~ $
```

ではGOPATHに指定したい、先ほどWindowsで確認したディレクトリへ移動します。ちなみにWindowsのCドライブはWSLで/mnt/c/に変換されます。先ほど確認したbin、srcが見えています。

```
~ $ cd /mnt/c/Users/tomakabe/go/
/mnt/c/Users/tomakabe/go $ ls
bin  src
```

ではここで実験。試しにパッケージをインポートしてみましょう。定番の[goimports](https://godoc.org/golang.org/x/tools/cmd/goimports)をインポートしてみます。わざとらしいですが、なんだか嫌な予感がします。

```
/mnt/c/Users/tomakabe/go $ go get -v golang.org/x/tools/cmd/goimports
Fetching https://golang.org/x/tools/cmd/goimports?go-get=1
Parsing meta tags from https://golang.org/x/tools/cmd/goimports?go-get=1 (status code 200)
get "golang.org/x/tools/cmd/goimports": found meta tag get.metaImport{Prefix:"golang.org/x/tools", VCS:"git", RepoRoot:"https://go.googlesource.com/tools"} at https://golang.org/x/tools/cmd/goimports?go-get=1
get "golang.org/x/tools/cmd/goimports": verifying non-authoritative meta tag
Fetching https://golang.org/x/tools?go-get=1
Parsing meta tags from https://golang.org/x/tools?go-get=1 (status code 200)
golang.org/x/tools (download)
created GOPATH=/home/tomakabe/go; see 'go help gopath'
```

嫌な予感は予定調和で的中します。GOPATHがいらっしゃらないので、/home/tomakabe/go とみなしてしまいました。先ほど確認した際、$HOMEはきれいな状態でした、が。新たにお作りになられたようです。

```
/mnt/c/Users/tomakabe/go $ ls ~/
go
/mnt/c/Users/tomakabe/go $ ls ~/go
bin  src
```

これではWSLとWindowsで、ソースもバイナリーも別々の管理になってしまいます。これはつらい。ああ、GOPATHを共有できればいいのに。

### そぞろ歩き その3(解決編)
そこで登場するのが、WSLENVです。Windowsで作業します。Windowsの環境変数GOPATHを、環境変数WSLENVへスイッチとともに設定します。/pスイッチは、「この環境変数はパスを格納しているから、いい感じにして」という指定です。

```
PS C:\Users\tomakabe\go\src\github.com\ToruMakabe\work> setx WSLENV "$env:WSLENV`:GOPATH/p"

成功: 指定した値は保存されました。
```

いい感じって何よ。それは環境に合わせたパス表現の変換です。WSLで見てみましょう。WSLENVを読ませる必要があるため、VS Codeをリロード後、ターミナルで確認します。


```
/mnt/c/Users/tomakabe/go $ echo $GOPATH
/mnt/c/Users/tomakabe/go
```

GOPATHが読めるようになりました。かつ、Windowsのパス表現であるC:\Users\tomakabe\goから、WSLの表現である/mnt/c/Users/tomakabe/goへと変換して渡しています。素晴らしい。これでGOPATHはひとつになり、ソースやバイナリー、パッケージの管理を統一できます。

ではWSLでサンプルコードを触ってみましょう。ソースのあるディレクトリへ移動します。ソースと先ほどビルドしたexeがあります。

```
/mnt/c/Users/tomakabe/go $ cd src/github.com/ToruMakabe/work/
/mnt/c/Users/tomakabe/go/src/github.com/ToruMakabe/work $ ls
hello.exe  hello.go
```

WSL上でビルドします。ELFバイナリー hello が作られました。

```
/mnt/c/Users/tomakabe/go/src/github.com/ToruMakabe/work $ go build hello.go
/mnt/c/Users/tomakabe/go/src/github.com/ToruMakabe/work $ ls
hello  hello.exe  hello.go
/mnt/c/Users/tomakabe/go/src/github.com/ToruMakabe/work $ file ./hello
./hello: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, not stripped
/mnt/c/Users/tomakabe/go/src/github.com/ToruMakabe/work $ ./hello
Hello Go on the new WSL
```

## まとめ

代表例としてGoの開発環境で説明しましたが、WSLENVは他の用途でも応用できるでしょう。スイッチの説明など、詳細は先ほど紹介した、[こちら](https://blogs.msdn.microsoft.com/commandline/2017/12/22/share-environment-vars-between-wsl-and-windows/)を。