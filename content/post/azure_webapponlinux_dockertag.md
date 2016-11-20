+++
Categories = ["Azure"]
Tags = ["Azure", "WebApp", "Linux", "Docker"]
date = "2016-11-20T13:00:00+09:00"
title = "Azure App Service on LinuxのコンテナをCLIで更新する方法"

+++

## CLIでコンテナを更新しよう
Connect(); 2016にあわせ、Azure App on Linuxのコンテナ対応が[発表](https://azure.microsoft.com/en-us/blog/app-service-on-linux-now-supports-containers-and-asp-net-core/)されました。Azure Container Serviceほどタップリマシマシな環境ではなく、サクッと楽してコンテナを使いたい人にオススメです。

さっそくデプロイの自動化どうすっかな、と検討している人もちらほらいらっしゃるようです。CI/CD側でビルド、テストしたコンテナをAPIなりCLIでApp Serviceにデプロイするやり口、どうしましょうか。

まだプレビューなのでAzure、VSTSなどCI/CD側の機能追加が今後あると思いますし、使い方がこなれてベストプラクティスが生まれるとは思いますが、アーリーアダプターなあなた向けに、現時点でできることを書いておきます。

## Azure CLI 2.0
Azure CLI 2.0に"appservice web config container"コマンドがあります。これでコンテナイメージを更新できます。

すでにyourrepoレポジトリのyourcontainerコンテナ、タグ1.0.0がデプロイされているとします。

```
$ az appservice web config container show -n yourcontainer -g YourRG
{
  "DOCKER_CUSTOM_IMAGE_NAME": "yourrepo/yourcontainer:1.0.0"
}
```

新ビルドのタグ1.0.1をデプロイするには、update -c オプションを使います。

```
$ az appservice web config container update -n yourcontainer -g YourRG -c "yourrepo/yourcontainer:1.0.1"
{
  "DOCKER_CUSTOM_IMAGE_NAME": "yourrepo/yourcontainer:1.0.1"
}
```

これで更新されます。