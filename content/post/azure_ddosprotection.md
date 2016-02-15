+++
Categories = ["Azure"]
Tags = ["Azure", "DDoS", "Securty"]
date = "2016-02-15T17:00:00+09:00"
title = "Azure DDoS対策ことはじめ"

+++

## すこぶるFAQ
攻撃者の荒ぶり具合が高まっており、ご相談いただく機会が増えました。「どうすればいいか見当がつかない」というケースも少なくないので、DDoSに絞り、現時点で検討していただきたいことをシンプルにまとめます。

## 公式ホワイトペーパー
[Microsoft Azure Network Security Whitepaper V3](http://download.microsoft.com/download/C/A/3/CA3FC5C0-ECE0-4F87-BF4B-D74064A00846/AzureNetworkSecurity_v3_Feb2015.pdf)が、現時点でのMicrosoft公式見解です。DDoS以外にもセキュリティ関連で考慮すべきことがまとまっています。おすすめです。

今回はここから、DDoSに言及している部分を抜き出し意訳します。必要に応じて補足も入れます。

### 2.2 Security Management and Threat Defense - Protecting against DDoS

    "To protect Azure platform services, Microsoft provides a distributed denial-of-service (DDoS) defense system that is part of Azure’s continuous monitoring process, and is continually improved through penetration-testing. Azure’s DDoS defense system is designed to not only withstand attacks from the outside, but also from other Azure tenants:"
    
MicrosoftはDDoSを防ぐ仕組みを提供しており、Azure外部からの攻撃はもちろんのこと、Azure内部で別テナントから攻撃されることも考慮しています。

## Azureがやってくれること
では、具体的に。

    "1. Network-layer high volume attacks. These attacks choke network pipes and packet processing capabilities by flooding the network with packets. The Azure DDoS defense technology provides detection and mitigation techniques such as SYN cookies, rate limiting, and connection limits to help ensure that such attacks do not impact customer environments."

ネットワークレイヤで検知できる力押しは、AzureのDDoS防御システムが検知、緩和します。このホワイトペーパーのAppendixで図解されていますが、IDS/IPSがその中心です。SYN Cookieやレート制限、コネクション制限などのテクニックを使います。

## お客様対応が必要なこと

ですが、アプリケーションレイヤの攻撃は、AzureのDDoS防御システムだけでは防ぎきれません。お客様のアプリや通信の内容、要件まで踏み込めないからです。

    "2. Application-layer attacks. These attacks can be launched against a customer VM. Azure does not provide mitigation or actively block network traffic affecting individual customer deployments, because the infrastructure does not interpret the expected behavior of customer applications. In this case, similar to on-premises deployments, mitigations include:"
 
 以下のような対処が有効です。
    
    "Running multiple VM instances behind a load-balanced Public IP address."
 
攻撃されるポイントを負荷分散装置のパブリックIPに限定し、複数のVMへ負荷を散らします。 攻撃されても、できる限り踏ん張るアプローチです。AzureのIDS/IPSで緩和しきれなかったトラフィックを受け止め、ダウンしないようにします。攻撃規模は事前に判断できないので、どれだけスケールさせるかは、ダウンした場合のビジネスインパクトとコストの兼ね合いで決める必要があります。
    
    "Using firewall proxy devices such as Web Application Firewalls (WAFs) that terminate and forward traffic to endpoints running in a VM. This provides some protection against a broad range of DoS and other attacks, such as low-rate, HTTP, and other application-layer threats. Some virtualized solutions, such as Barracuda Networks, are available that perform both intrusion detection and prevention."

WAFを入れて、通信の中身を見ないとわからない攻撃を検知、緩和します。一見ノーマルなトラフィックでも「ゆっくりと攻撃」するようなケースもあります。たとえば、ゆっくりWebサーバのコネクションを枯渇させるような攻撃など。Azureでは仮想アプライアンスとして、Barracuda NetworksのWAFなどが使えます。

    " Web Server add-ons that protect against certain DoS attacks."

Webサーバへアドインを入れましょう。パッチも適用しましょう。構成も見直しましょう。ちょっと古いですが[ここ](http://blogs.msdn.com/b/friis/archive/2014/12/30/security-guidelines-to-detect-and-prevent-dos-attacks-targeting-iis-azure-web-role-paas.aspx)が参考になります。
    
    "Network ACLs, which can prevent packets from certain IP addresses from reaching VMs."
    
もしブロックしたいアクセス元IPアドレスがわかるなら、ACLで遮断しましょう。逆に通信可能な範囲のみ指定することもできます。

## ホワイトペーパーに加えて
[CDN](https://azure.microsoft.com/ja-jp/services/cdn/)も有効ですので検討ください。2段構えでの負荷分散、防御ができます。Akamaiとの統合ソリューションも今後[提供される予定](https://azure.microsoft.com/ja-jp/blog/microsoft-and-akamai-bring-cdn-to-azure-customers/)です。

CDNは常に世界中からのトラフィックで揉まれているだけあって、DDoS防御四天王で最強の漢が最初に出てくるくらい強力です。


最後に。攻撃されている感があれば、カスタマーサポートまで。
