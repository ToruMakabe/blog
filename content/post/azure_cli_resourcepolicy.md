+++
Categories = ["Azure"]
Tags = ["Azure", "CLI", "Resource Policy"]
date = "2016-05-21T11:00:00+09:00"
title = "Azure X-Plat CLIでResource Policyを設定する"

+++

## Azure X-Plat CLIのリリースサイクル
OSS/Mac/Linux派なAzurerの懐刀、Azure X-Plat CLIのリリースサイクルは、おおよそ[月次](https://github.com/Azure/azure-xplat-cli/releases)です。改善と機能追加を定期的にまわしていくことには意味があるのですが、いっぽう、Azureの機能追加へタイムリーに追随できないことがあります。短期間とはいえ、次のリリースまで空白期間ができてしまうのです。

たとえば、今回のテーマであるResource Policy。GA直後に公開された[ドキュメント](https://azure.microsoft.com/ja-jp/documentation/articles/resource-manager-policy/)に、X-Plat CLIでの使い方が2016/5/21現在書かれていません。おやCLIではできないのかい、と思ってしまいますね。でもその後のアップデートで、できるようになりました。

機能リリース時点ではCLIでできなかった、でもCLIの月次アップデートで追加された、いまはできる、ドキュメントの更新待ち。こんなパターンは多いので、あきらめずに探ってみてください。

## ポリシーによるアクセス管理
さて本題。リソースの特性に合わせて、きめ細かいアクセス管理をしたいことがあります。

* VMやストレージのリソースタグに組織コードを入れること強制し、費用負担の計算に使いたい
* 日本国外リージョンのデータセンタを使えないようにしたい
* Linuxのディストリビューションを標準化し、その他のディストリビューションは使えなくしたい
* 開発環境リソースグループでは、大きなサイズのインスタンスを使えないようにしたい

などなど。こういう課題にポリシーが効きます。

従来からあるRBACは「役割と人」目線です。「この役割を持つ人は、このリソースを読み取り/書き込み/アクションできる」という表現をします。[組み込みロールの一覧](https://azure.microsoft.com/ja-jp/documentation/articles/role-based-access-built-in-roles/)を眺めると、理解しやすいでしょう。

ですが、RBACは役割と人を切り口にしているので、各リソースの多様な特性にあわせた統一表現が難しいです。たとえばストレージにはディストリビューションという属性はありません。無理してカスタム属性なんかで表現すると破綻しそうです。

リソース目線でのアクセス管理もあったほうがいい、ということで、ポリシーの出番です。

## X-Plat CLIでの定義方法
2016/4リリースの[v0.9.20](https://github.com/Azure/azure-xplat-cli/releases/tag/v0.9.20-April2016)から、X-Plat CLIでもResource Policyを定義できます。

ポリシーの定義、構文はPowerShellと同じなので、公式ドキュメントに任せます。ご一読を。

**[ポリシーを使用したリソース管理とアクセス制御](https://azure.microsoft.com/ja-jp/documentation/articles/resource-manager-policy/)**

X-Plat CLI固有部分に絞って紹介します。

### ポリシー定義ファイルを作る
CLIに直書きもできるようですが、人類には早すぎる気がします。ここではファイルに書きます。

例として、作成できるVMのサイズを限定してみましょう。開発環境などでよくあるパターンと思います。VM作成時、Standard_D1～5_v2に当てはまらないVMサイズが指定されると、拒否します。


```
{
  "if": {
    "allOf": [
      {
        "field": "type",
        "equals": "Microsoft.Compute/virtualMachines"
      },
      {
        "not": {
          "field": "Microsoft.Compute/virtualMachines/sku.name",
          "in": [ "Standard_D1_v2", "Standard_D2_v2","Standard_D3_v2", "Standard_D4_v2", "Standard_D5_v2" ]
        }
      }
    ]
  },
  "then": {
    "effect": "deny"
  }
}
```
policy_deny_vmsize.json というファイル名にしました。では投入。ポリシー名は deny_vmsize とします。

```
$ azure policy definition create -n deny_vmsize -p ./policy_deny_vmsize.json
```
```
info:    Executing command policy definition create
+ Creating policy definition deny_vmsize
data:    PolicyName:             deny_vmsize
data:    PolicyDefinitionId:     /subscriptions/mysubscription/providers/Microsoft.Authorization/policyDefinitions/deny_vmsize
data:    PolicyType:             Custom
data:    DisplayName:
data:    Description:
data:    PolicyRule:             allOf=[field=type, equals=Microsoft.Compute/virtualMachines, field=Microsoft.Compute/virtualMachines/sku.name, in=[Standard_D1_v2, Standard_D2_v2, Standard_D3_v2, Standard_D4_v2, Standard_D5_v2]], effect=deny
info:    policy definition create command OK
```
できたみたいです。

### ポリシーをアサインする
では、このポリシーを割り当てます。割り当ての範囲(スコープ)はサブスクリプションとします。リソースグループなど、より細かいスコープも[指定可能](https://msdn.microsoft.com/ja-jp/library/azure/mt588464.aspx)です。
```
$ azure policy assignment create -n deny_vmsize_assignment -p /subscriptions/mysubscription/providers/Microsoft.Authorization/policyDefinitions/deny_vmsize -s /subscriptions/mysubscription
```
```
info:    Executing command policy assignment create
+ Creating policy assignment deny_vmsize_assignment
data:    PolicyAssignmentName:     deny_vmsize_assignment
data:    Type:                     Microsoft.Authorization/policyAssignments
data:    DisplayName:
data:    PolicyDefinitionId:       /subscriptions/mysubscription/providers/Microsoft.Authorization/policyDefinitions/deny_vmsize
data:    Scope:                    /subscriptions/mysubscription
info:    policy assignment create command OK
```
割り当て完了。では試しに、このサブスクリプションに属するユーザで、Gシリーズのゴジラ級インスタンスを所望してみます。
```
$ azure vm quick-create -g RPPoC -n rppocvm westus -y Linux -Q "canonical:ubuntuserver:14.04.4-LTS:latest" -u "adminname" -p "adminpass" -z Standard_G5
info:    Executing command vm quick-create
[...snip]
+ Creating VM "rppocvm"
error:   The resource action 'Microsoft.Compute/virtualMachines/write' is disallowed by one or more policies. Policy identifier(s): '/subscriptions/mysubscription/providers/Microsoft.Authorization/policyDefinitions/deny_vmsize'.
info:    Error information has been recorded to /root/.azure/azure.err
error:   vm quick-create command failed
```
拒否られました。

許可されているVMサイズだと。
```
$ azure vm quick-create -g RPPoC -n rppocvm westus -y Linux -Q "canonical:ubuntuserver:14.04.4-LTS:latest" -u "adminname" -p "adminpass" -z Standard_D1_v2
info:    Executing command vm quick-create
[...snip]
info:    vm quick-create command OK
```
成功。