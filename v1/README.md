# RoadMap
## V1
- 存储核心 : 单片上传
- 加上B端注册管理
- B端权限访问

## V2
- 存储核心 : 分片上传
- ISP的存储数据Stable化(适情况而定)

## V3
- HTTP Support
- Certificated Data Support

## V4
- Stable BTree Map

# 核心设计
## Cycle管理
### Bucket和ISP均实现自监测和阈值Top Up
- 自监测的意思是： 当有Update Call的时候，每次执行UpdateCall都监测当前Cycle情况，如果Cycle到达阈值就自动给自己TopUp Cycles
- 阈值控制： 一个Block执行Cycle的上限是9B Cycle， 由此推算自动Top Up的阈值Cycle
- 外部主动触发： 外部设立Heartbeat Canister , 监测Cycle和ICP
- PS： 
- 第一： 需要注意的是： 当前的ISP版本， Bucket只有当存储时才会不断触发Update Call
- 第二： 可以采用 定时让Heartbeat主动触发Bucket和ISP的自监测函数，各自负责各自的Cycle情况
- 第三： Heartbeat主要负责ICP的充值， 定时检测Bucket的ICP余额，如果不够了给他充值

## Error Handle
- 决不允许Trap发生
- 如果出错，记录到Bucket的Error Set中， 记录好所有数据


# 悬而未决的几个问题
- 分片存储后的索引方案，对应的HTTP Get CallBack请求：重新向ISP请求还是在Bucket中重定向
- ISP Canister能存多少个Key, 如果ISP满了怎么办，什么时候会满?

# 相关资料
- [官网Cycle消耗说明表](https://smartcontracts.org/docs/developers-guide/computation-and-storage-costs.html)
- [源码Cycle消耗说明表](https://github.com/dfinity/ic/blob/master/rs/config/src/subnet_config.rs)
- [icp -> cycle 示例](https://github.com/C-B-Elite/icp_to_cycle)