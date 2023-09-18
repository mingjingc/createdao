# CreateDAO: A Decentrailization Create Platform 去中心化创作平台

## Introduction

目前中心化的创作平台抽成大，而且未来的抽成比例决定由，极大损害了创作者的利益与积极性。比如B站抽成规则: “硬币”分享收入比例为7:3，“大会员”分享收入11:9。去中心化创作平台可以降低抽成比例，未来的治理由创作者投票决定。

## Contract Overview

![overview](./overview.png)

- create合约: 创作者注册账户信息，新建作品；用户给作品点赞、打赏

- market合约: 创作者将作品挂到交易市场，在此期间用户的打赏仍然属于创作者; 创作者还可以挂作品广告位租赁单(未来要做)

- dao合约: 任何人可以发起任务提案，由创作者投票决定是否批准资金，创作者的投票权重暂时由贡献值决定。

  ​              创作者给dao金库贡献的资金都会获得一定贡献值。

合约地址: 0xe0baae8ab1cc21a9be1d0df2c74af2661a037a494eb5cba1fed7e0984bb3d65d(devnet)
