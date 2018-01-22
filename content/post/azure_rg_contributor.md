+++
Categories = ["Azure"]
Tags = ["Azure", "RBAC"]
date = "2018-01-22T22:00:00+09:00"
title = "Azureのリソースグループ限定 共同作成者をいい感じに作る"

+++

## 共同作成者は、ちょっと強い
Azureのリソースグループは、リソースを任意のグループにまとめ、ライフサイクルや権限の管理を一括して行える便利なコンセプトです。

ユースケースのひとつに、"本番とは分離した開発向けリソースグループを作って、アプリ/インフラ開発者に開放したい"、があります。新しい技術は試行錯誤で身につくので、こういった環境は重要です。

なのですが、このようなケースで、権限付与の落とし穴があります。

* サブスクリプション所有者が開発用リソースグループを作る
* スコープを開発用リソースグループに限定し、開発者に対し共同作成者ロールを割り当てる
* 開発者はリソースグループ限定で、のびのび試行錯誤できて幸せ
* 開発者がスッキリしたくなり、リソースグループごとバッサリ削除 (共同作成者なので可能)
* 開発者にはサブスクリプションレベルの権限がないため、リソースグループを作成できない
* 詰む
* サブスクリプション所有者が、リソースグループ作成と権限付与をやり直し

共同作成者ロールから、リソースグループの削除権限だけを除外できると、いいんですが。そこでカスタムロールの出番です。リソースグループ限定、グループ削除権限なしの共同作成者を作ってみましょう。

## いい感じのカスタムロールを作る
Azureのカスタムロールは、個別リソースレベルで粒度の細かい権限設定ができます。ですが、やり過ぎると破綻するため、シンプルなロールを最小限作る、がおすすめです。

シンプルに行きましょう。まずはカスタムロールの定義を作ります。role.jsonとします。

```
{
    "Name": "Resource Group Contributor",
    "IsCustom": true,
    "Description": "Lets you manage everything except access to resources, but can not delete Resouce Group",
    "Actions": [
        "*"
    ],
    "NotActions": [
        "Microsoft.Authorization/*/Delete",
        "Microsoft.Authorization/*/Write",
        "Microsoft.Authorization/elevateAccess/Action",
        "Microsoft.Resources/subscriptions/resourceGroups/Delete"
    ],
    "AssignableScopes": [
        "/subscriptions/your-subscriotion-id"
    ]
}
```

組み込みロールの共同作成者をテンプレに、NotActionsでリソースグループの削除権限を除外しました。AssignableScopesでリソースグループを限定してもいいですが、リソースグループの数だけロールを作るのはつらいので、ここでは指定しません。後からロールを割り当てる時にスコープを指定します。

では、カスタムロールを作成します。

```
$ az role definition create --role-definition ./role.json
```

出力にカスタムロールのIDが入っていますので、控えておきます。

```
"id": "/subscriptions/your-subscriotion-id/providers/Microsoft.Authorization/roleDefinitions/your-customrole-id"
```

## カスタムロールをユーザー、グループ、サービスプリンシパルに割り当てる
次に、ユーザー/グループに先ほど作ったカスタムロールを割り当てます。スコープはリソースグループに限定します。

```
$ az role assignment create --assignee-object-id your-user-or-group-object-id --role your-customrole-id --scope "/subscriptions/your-subscriotion-id/resourceGroups/sample-dev-rg"
```

サービスプリンシパル作成時に割り当てる場合は、以下のように。

```
$ az ad sp create-for-rbac -n "rgcontributor" -p "your-password" --role your-customrole-id --scopes "/subscriptions/your-subscriotion-id/resourceGroups/sample-dev-rg"
```

余談ですが、"az ad sp create-for-rbac"コマンドはAzure ADアプリケーションを同時に作るため、別途アプリを作ってサービスプリンシパルと紐づける、という作業が要りません。

## 試してみる
ログインして試してみましょう。サービスプリンシパルの例です。

```
$ az login --service-principal -u "http://rgcontributor" -p "your-password" -t "your-tenant-id"
```

検証したサブスクリプションには多数のリソースグループがあるのですが、スコープで指定したものだけが見えます。

```
$ az group list -o table
Name              Location    Status
----------------  ----------  ---------
sample-dev-rg  japaneast   Succeeded
```

このリソースグループに、VMを作っておきました。リストはしませんが、ストレージやネットワークなど関連リソースもこのグループにあります。

```
$ az vm list -o table
Name              ResourceGroup     Location
----------------  ----------------  ----------
sampledevvm01     sample-dev-rg  japaneast
```

試しにリソースグループを作ってみます。サブスクリプションスコープの権限がないため怒られます。

```
$ az group create -n rgc-poc-rg -l japaneast
The client 'aaaaa-bbbbb-ccccc-ddddd-eeeee' with object id 'aaaaa-bbbbb-ccccc-ddddd-eeeee' does not have authorization to perform action 'Microsoft.Resources/subscriptions/resourcegroups/write' over scope '/subscriptions/your-subscriotion-id/resourcegroups/rgc-poc-rg'.
```

リソースグループを消してみます。消すかい？ -> y -> ダメ、という、持ち上げて落とす怒り方です。

```
$ az group delete -n sample-dev-rg
Are you sure you want to perform this operation? (y/n): y
The client 'aaaaa-bbbbb-ccccc-ddddd-eeeee' with object id 'aaaaa-bbbbb-ccccc-ddddd-eeeee' does not have authorization to perform action 'Microsoft.Resources/subscriptions/resourcegroups/delete' over scope '/subscriptions/your-subscriotion-id/resourcegroups/sample-dev-rg'.
```

## でもリソースグループのリソースを一括削除したい
でも、リソースグループは消せなくても、リソースをバッサリ消す手段は欲しいですよね。そんな時には空のリソースマネージャーテンプレートを、completeモードでデプロイすると、消せます。

空テンプレートを、empty.jsonとしましょう。

```
{
    "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "variables": {},
    "resources": [],
    "outputs": {}
}
```

破壊的空砲を打ちます。

```
$ az group deployment create --mode complete -g sample-dev-rg --template-file ./empty.json
```

リソースグループは残ります。

```
$ az group list -o table
Name              Location    Status
----------------  ----------  ---------
sample-dev-rg  japaneast   Succeeded
```

VMは消えました。リストしませんが、他の関連リソースもバッサリ消えています。

```
$ az vm list -o table

```