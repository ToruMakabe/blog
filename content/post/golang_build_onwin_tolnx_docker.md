+++
Categories = ["Windows"]
Tags = ["Windows", "Golang", "Docker"]
date = "2017-12-04T22:00:00+09:00"
title = "Windows上でLinux向けGoバイナリをDockerでビルドする"

+++

## 小ネタです
Goはクロスプラットフォーム開発しやすい言語なのですが、Windows上でLinux向けバイナリーをビルドするなら、gccが要ります。正直なところ入れたくありません。なのでDockerでやります。

## 条件
* Docker for Windows
  * Linuxモード
  * ドライブ共有

## PowerShell窓で実行
ビルドしたいGoのソースがあるディレクトリで以下のコマンドを実行します。Linux向けバイナリーが同じディレクトリに出来ます。

```
docker run --rm -it -e GOPATH=/go --mount type=bind,source=${env:GOPATH},target=/go --mount type=bind,source=${PWD},target=/work -w /work golang:1.9.2-alpine go build -o yourapp_linux
```

* golang:1.9.2-alpine DockerイメージはGOPATHに/goを[設定して](https://github.com/docker-library/golang/blob/0f5ee2149d00dcdbf48fca05acf582e45d8fa9a5/1.9/alpine3.6/Dockerfile)ビルドされていますが、念のため実行時にも設定
* -v オプションでのマウントは[非推奨](https://docs.docker.com/engine/admin/volumes/bind-mounts/)になったので --mount で