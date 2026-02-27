# md-glance 渲染能力测试文档

本文档包含复杂的 Mermaid 图表、LaTeX 数学公式及各类 GFM 语法，用于全面测试 Markdown 阅读器的渲染能力。

---

## 一、数学公式

### 1.1 行内公式

爱因斯坦质能方程 $E = mc^2$ 是物理学中最著名的公式之一。欧拉恒等式 $e^{i\pi} + 1 = 0$ 被誉为"最优美的数学公式"。薛定谔方程中，波函数 $\Psi(\mathbf{r}, t)$ 满足归一化条件 $\int_{-\infty}^{\infty} |\Psi|^2 \, dx = 1$。贝叶斯定理 $P(A|B) = \frac{P(B|A) \cdot P(A)}{P(B)}$ 是概率论的基石。

### 1.2 极限与微积分

$$
\lim_{n \to \infty} \left(1 + \frac{1}{n}\right)^n = e
$$

$$
\frac{d}{dx}\left[\int_{a}^{x} f(t)\,dt\right] = f(x)
$$

$$
\int_0^\infty e^{-x^2} \, dx = \frac{\sqrt{\pi}}{2}
$$

$$
\oint_C \mathbf{F} \cdot d\mathbf{r} = \iint_S (\nabla \times \mathbf{F}) \cdot d\mathbf{S}
$$

### 1.3 级数与求和

$$
\sum_{n=0}^{\infty} \frac{x^n}{n!} = e^x
$$

$$
\prod_{p \text{ prime}} \frac{1}{1 - p^{-s}} = \sum_{n=1}^{\infty} \frac{1}{n^s} = \zeta(s), \quad \Re(s) > 1
$$

$$
\sum_{k=0}^{n} \binom{n}{k} x^k y^{n-k} = (x + y)^n
$$

### 1.4 矩阵与线性代数

$$
A = \begin{pmatrix}
a_{11} & a_{12} & \cdots & a_{1n} \\
a_{21} & a_{22} & \cdots & a_{2n} \\
\vdots & \vdots & \ddots & \vdots \\
a_{m1} & a_{m2} & \cdots & a_{mn}
\end{pmatrix}
$$

$$
\det(A) = \sum_{\sigma \in S_n} \text{sgn}(\sigma) \prod_{i=1}^{n} a_{i,\sigma(i)}
$$

$$
\begin{bmatrix}
1 & 0 & 0 \\
0 & \cos\theta & -\sin\theta \\
0 & \sin\theta & \cos\theta
\end{bmatrix}
\begin{bmatrix} x \\ y \\ z \end{bmatrix}
=
\begin{bmatrix} x \\ y\cos\theta - z\sin\theta \\ y\sin\theta + z\cos\theta \end{bmatrix}
$$

### 1.5 分段函数与方程组

$$
f(x) = \begin{cases}
\displaystyle\frac{x^2 - 1}{x - 1} & \text{if } x \neq 1 \\[10pt]
2 & \text{if } x = 1
\end{cases}
$$

$$
\begin{aligned}
\nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \\[6pt]
\nabla \cdot \mathbf{B} &= 0 \\[6pt]
\nabla \times \mathbf{E} &= -\frac{\partial \mathbf{B}}{\partial t} \\[6pt]
\nabla \times \mathbf{B} &= \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
\end{aligned}
$$

### 1.6 复杂嵌套公式

$$
\mathcal{L}\{f(t)\} = \int_0^{\infty} f(t) \, e^{-st} \, dt = F(s)
$$

$$
\hat{f}(\xi) = \int_{-\infty}^{\infty} f(x) \, e^{-2\pi i x \xi} \, dx
$$

$$
\cfrac{1}{1 + \cfrac{1}{2 + \cfrac{1}{3 + \cfrac{1}{4 + \cdots}}}} = \frac{e - 1}{e + 1}
$$

$$
\underbrace{\int \cdots \int}_{n} f(x_1, x_2, \ldots, x_n) \, dx_1 \, dx_2 \cdots dx_n
$$

---

## 二、Mermaid 图表

### 2.1 复杂流程图（含子图）

```mermaid
flowchart TB
    subgraph 客户端["🖥️ 客户端"]
        A[用户请求] --> B{认证检查}
        B -->|已认证| C[生成 Token]
        B -->|未认证| D[登录页面]
        D --> E[输入凭证]
        E --> F{验证凭证}
        F -->|成功| C
        F -->|失败| G[错误提示]
        G --> D
    end

    subgraph 网关["🌐 API 网关"]
        H[负载均衡] --> I{路由分发}
        I -->|/api/user| J[用户服务]
        I -->|/api/order| K[订单服务]
        I -->|/api/product| L[商品服务]
        I -->|/api/pay| M[支付服务]
    end

    subgraph 数据层["💾 数据层"]
        N[(MySQL 主库)]
        O[(MySQL 从库)]
        P[(Redis 缓存)]
        Q[(Elasticsearch)]
        N -->|主从复制| O
    end

    C --> H
    J --> P
    J --> N
    K --> N
    K --> P
    L --> Q
    L --> O
    M --> N

    style 客户端 fill:#e1f5fe,stroke:#01579b
    style 网关 fill:#f3e5f5,stroke:#4a148c
    style 数据层 fill:#e8f5e9,stroke:#1b5e20
```

### 2.2 时序图

```mermaid
sequenceDiagram
    autonumber
    actor 用户
    participant 前端 as 前端应用
    participant GW as API 网关
    participant Auth as 认证服务
    participant BIZ as 业务服务
    participant DB as 数据库
    participant MQ as 消息队列
    participant Cache as Redis

    用户->>前端: 发起操作请求
    前端->>GW: HTTP 请求 + JWT
    
    GW->>Cache: 查询 Token 黑名单
    Cache-->>GW: Token 有效
    
    GW->>Auth: 验证 & 解析 Token
    Auth-->>GW: 用户身份信息
    
    GW->>BIZ: 转发请求 + 用户上下文
    
    BIZ->>Cache: 查询缓存
    alt 缓存命中
        Cache-->>BIZ: 返回缓存数据
    else 缓存未命中
        BIZ->>DB: 查询数据
        DB-->>BIZ: 返回结果
        BIZ->>Cache: 写入缓存
    end
    
    BIZ->>MQ: 发送异步事件
    BIZ-->>GW: 响应数据
    GW-->>前端: HTTP 响应
    前端-->>用户: 展示结果
    
    Note over MQ,DB: 异步处理流程
    MQ->>BIZ: 消费事件
    BIZ->>DB: 更新统计数据
```

### 2.3 类图

```mermaid
classDiagram
    class Animal {
        <<abstract>>
        +String name
        +int age
        #String habitat
        +makeSound()* void
        +move() void
        +toString() String
    }
    
    class Mammal {
        +float bodyTemperature
        +nurse() void
    }
    
    class Bird {
        +float wingspan
        +fly() void
        +layEggs() void
    }
    
    class Dog {
        +String breed
        +makeSound() void
        +fetch() void
    }
    
    class Cat {
        +boolean isIndoor
        +makeSound() void
        +purr() void
    }
    
    class Eagle {
        +float maxAltitude
        +makeSound() void
        +hunt() void
    }
    
    class ISwimmable {
        <<interface>>
        +swim() void
        +dive(depth: float) void
    }
    
    class ITrainable {
        <<interface>>
        +train(command: String) bool
        +getSkills() List~String~
    }

    Animal <|-- Mammal
    Animal <|-- Bird
    Mammal <|-- Dog
    Mammal <|-- Cat
    Bird <|-- Eagle
    ISwimmable <|.. Dog : implements
    ITrainable <|.. Dog : implements
    ITrainable <|.. Eagle : implements
```

### 2.4 状态图

```mermaid
stateDiagram-v2
    [*] --> 待支付
    
    state 待支付 {
        [*] --> 创建订单
        创建订单 --> 选择支付方式
        选择支付方式 --> 发起支付
    }
    
    待支付 --> 支付中: 用户确认支付
    
    state 支付中 {
        [*] --> 等待回调
        等待回调 --> 验证签名
        验证签名 --> 更新状态
    }
    
    支付中 --> 已支付: 支付成功
    支付中 --> 支付失败: 支付超时/异常
    支付失败 --> 待支付: 重新支付
    支付失败 --> 已取消: 用户取消
    
    已支付 --> 待发货: 商家确认
    待发货 --> 已发货: 物流揽收
    已发货 --> 已签收: 用户签收
    已签收 --> 已完成: 确认收货
    已签收 --> 退货中: 申请退货
    退货中 --> 已退款: 退货完成
    退货中 --> 已完成: 取消退货
    
    已取消 --> [*]
    已完成 --> [*]
    已退款 --> [*]
```

### 2.5 甘特图

```mermaid
gantt
    title 产品开发路线图 2026 Q1
    dateFormat YYYY-MM-DD
    axisFormat %m/%d

    section 需求阶段
        市场调研           :done,    r1, 2026-01-06, 10d
        竞品分析           :done,    r2, after r1, 5d
        需求评审           :done,    r3, after r2, 3d
    
    section 设计阶段
        系统架构设计       :done,    d1, after r3, 7d
        UI/UX 设计         :done,    d2, after r3, 12d
        数据库设计         :done,    d3, after d1, 5d
        API 接口设计       :done,    d4, after d1, 5d
    
    section 开发阶段
        基础框架搭建       :active,  e1, after d3, 7d
        用户模块           :         e2, after e1, 10d
        订单模块           :         e3, after e1, 12d
        支付模块           :         e4, after e2, 8d
        通知模块           :         e5, after e3, 6d
    
    section 测试阶段
        单元测试           :         t1, after e2, 15d
        集成测试           :         t2, after e4, 10d
        性能测试           :crit,    t3, after t2, 7d
        安全审计           :crit,    t4, after t2, 5d
    
    section 上线
        灰度发布           :milestone, m1, after t3, 0d
        全量发布           :milestone, m2, after m1, 7d
```

### 2.6 饼图

```mermaid
pie showData
    title 前端框架市场份额 (2026)
    "React" : 38.5
    "Vue.js" : 24.2
    "Angular" : 15.8
    "Svelte" : 9.3
    "Solid" : 5.1
    "其他" : 7.1
```

### 2.7 ER 图

```mermaid
erDiagram
    USER ||--o{ ORDER : places
    USER {
        bigint id PK
        varchar username UK
        varchar email UK
        varchar password_hash
        enum status
        timestamp created_at
        timestamp updated_at
    }
    
    ORDER ||--|{ ORDER_ITEM : contains
    ORDER {
        bigint id PK
        bigint user_id FK
        varchar order_no UK
        decimal total_amount
        enum status
        text remark
        timestamp created_at
    }
    
    ORDER_ITEM }|--|| PRODUCT : references
    ORDER_ITEM {
        bigint id PK
        bigint order_id FK
        bigint product_id FK
        int quantity
        decimal unit_price
        decimal subtotal
    }
    
    PRODUCT ||--o{ PRODUCT_SKU : has
    PRODUCT {
        bigint id PK
        bigint category_id FK
        varchar name
        text description
        enum status
        timestamp created_at
    }
    
    CATEGORY ||--o{ PRODUCT : contains
    CATEGORY {
        bigint id PK
        bigint parent_id FK
        varchar name
        int sort_order
    }
    
    PRODUCT_SKU {
        bigint id PK
        bigint product_id FK
        varchar sku_code UK
        decimal price
        int stock
        json attributes
    }
    
    ORDER }|--|| PAYMENT : "paid via"
    PAYMENT {
        bigint id PK
        bigint order_id FK
        varchar transaction_no UK
        decimal amount
        enum channel
        enum status
        timestamp paid_at
    }
```

### 2.8 Git 图

```mermaid
gitGraph
    commit id: "init"
    commit id: "v0.1.0"
    branch feature/auth
    checkout feature/auth
    commit id: "add login"
    commit id: "add register"
    commit id: "add JWT"
    checkout main
    branch feature/order
    checkout feature/order
    commit id: "order model"
    commit id: "order API"
    checkout main
    merge feature/auth id: "merge auth" tag: "v0.2.0"
    checkout feature/order
    commit id: "order test"
    checkout main
    merge feature/order id: "merge order"
    commit id: "hotfix: XSS" type: REVERSE
    branch release/1.0
    checkout release/1.0
    commit id: "bump version"
    commit id: "update docs"
    checkout main
    merge release/1.0 id: "v1.0.0" tag: "v1.0.0"
```

### 2.9 用户旅程图

```mermaid
journey
    title 用户网购体验旅程
    section 发现商品
        搜索商品: 3: 用户
        浏览列表: 3: 用户
        查看详情: 4: 用户
        阅读评价: 4: 用户
    section 下单购买
        加入购物车: 5: 用户
        选择规格: 3: 用户
        填写地址: 2: 用户
        确认支付: 4: 用户, 支付系统
    section 等待收货
        查看物流: 3: 用户, 物流
        联系客服: 2: 用户, 客服
        确认签收: 5: 用户, 物流
    section 售后
        评价商品: 4: 用户
        申请退货: 2: 用户, 客服
```

---

## 三、GFM 扩展语法

### 3.1 任务列表

- [x] 支持基础 Markdown 渲染
- [x] 支持 GFM 表格
- [x] 支持代码高亮
- [x] 支持 KaTeX 数学公式
- [x] 支持 Mermaid 图表
- [ ] 支持脚注
- [ ] 支持自定义主题

### 3.2 复杂表格

| 算法 | 平均时间复杂度 | 最坏时间复杂度 | 空间复杂度 | 稳定性 |
|:---|:---:|:---:|:---:|:---:|
| 冒泡排序 | $O(n^2)$ | $O(n^2)$ | $O(1)$ | ✅ 稳定 |
| 快速排序 | $O(n \log n)$ | $O(n^2)$ | $O(\log n)$ | ❌ 不稳定 |
| 归并排序 | $O(n \log n)$ | $O(n \log n)$ | $O(n)$ | ✅ 稳定 |
| 堆排序 | $O(n \log n)$ | $O(n \log n)$ | $O(1)$ | ❌ 不稳定 |
| 计数排序 | $O(n + k)$ | $O(n + k)$ | $O(k)$ | ✅ 稳定 |
| 基数排序 | $O(nk)$ | $O(nk)$ | $O(n + k)$ | ✅ 稳定 |

### 3.3 多语言代码块

**Swift:**

```swift
protocol MarkdownRenderer {
    associatedtype Output
    func render(_ markdown: String) async throws -> Output
}

struct HTMLRenderer: MarkdownRenderer {
    typealias Output = String
    
    private let options: RenderOptions
    
    func render(_ markdown: String) async throws -> String {
        let ast = try Parser.parse(markdown)
        return ast.accept(HTMLVisitor(options: options))
    }
}

extension HTMLRenderer {
    struct RenderOptions: Sendable {
        var enableMath: Bool = true
        var enableMermaid: Bool = true
        var theme: Theme = .auto
        
        enum Theme: String, Sendable {
            case light, dark, auto
        }
    }
}
```

**Python:**

```python
from typing import TypeVar, Generic, Callable
from dataclasses import dataclass, field
from functools import reduce

T = TypeVar('T')
U = TypeVar('U')

@dataclass(frozen=True)
class Result(Generic[T]):
    value: T | None = None
    error: Exception | None = None
    
    def map(self, f: Callable[[T], U]) -> 'Result[U]':
        if self.error:
            return Result(error=self.error)
        try:
            return Result(value=f(self.value))
        except Exception as e:
            return Result(error=e)
    
    def flat_map(self, f: Callable[[T], 'Result[U]']) -> 'Result[U]':
        if self.error:
            return Result(error=self.error)
        return f(self.value)

pipeline = [
    lambda x: Result(value=x * 2),
    lambda x: Result(value=x + 10),
    lambda x: Result(value=x ** 0.5),
]

result = reduce(lambda r, f: r.flat_map(f), pipeline, Result(value=42))
```

**Rust:**

```rust
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Debug, Clone)]
struct Cache<K: Eq + Hash, V: Clone> {
    store: Arc<RwLock<HashMap<K, (V, Instant)>>>,
    ttl: Duration,
}

impl<K: Eq + Hash + Clone, V: Clone> Cache<K, V> {
    async fn get_or_insert<F, Fut>(&self, key: K, f: F) -> Result<V, Error>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<V, Error>>,
    {
        {
            let store = self.store.read().await;
            if let Some((value, inserted_at)) = store.get(&key) {
                if inserted_at.elapsed() < self.ttl {
                    return Ok(value.clone());
                }
            }
        }
        
        let value = f().await?;
        let mut store = self.store.write().await;
        store.insert(key, (value.clone(), Instant::now()));
        Ok(value)
    }
}
```

### 3.4 引用嵌套

> **定理（中心极限定理）**
> 
> 设 $X_1, X_2, \ldots, X_n$ 为独立同分布的随机变量序列，期望 $\mu = E(X_i)$，方差 $\sigma^2 = D(X_i) > 0$，则：
> 
> $$\lim_{n \to \infty} P\left(\frac{\sum_{i=1}^{n} X_i - n\mu}{\sigma\sqrt{n}} \leq x\right) = \Phi(x)$$
> 
> 其中 $\Phi(x)$ 是标准正态分布函数。
> 
> > **推论：** 当 $n$ 足够大时，$\bar{X} \sim N\left(\mu, \frac{\sigma^2}{n}\right)$ 近似成立。

### 3.5 脚注与链接混排

这段文字包含 [内联链接](https://example.com "示例")、**粗体**、*斜体*、~~删除线~~、`行内代码`，以及一个公式 $\Gamma(n) = (n-1)!$ 的复杂混排测试。

---

## 四、压力测试：公式与图表混合

下面测试公式与图表在同一章节中的渲染稳定性。

傅里叶级数将周期函数分解为三角函数之和：

$$
f(x) = \frac{a_0}{2} + \sum_{n=1}^{\infty} \left[ a_n \cos\left(\frac{2\pi n x}{T}\right) + b_n \sin\left(\frac{2\pi n x}{T}\right) \right]
$$

其信号处理流程如下：

```mermaid
flowchart LR
    A["原始信号 x(t)"] --> B["采样 A/D"]
    B --> C["加窗 w(n)"]
    C --> D["FFT 变换"]
    D --> E{"频谱分析"}
    E -->|低频| F["低通滤波"]
    E -->|高频| G["高通滤波"]
    E -->|带通| H["带通滤波"]
    F --> I["IFFT 逆变换"]
    G --> I
    H --> I
    I --> J["重建信号 y(t)"]
```

其中 FFT 的复杂度为 $O(N \log N)$，相较于 DFT 的 $O(N^2)$ 有显著提升。离散傅里叶变换定义为：

$$
X[k] = \sum_{n=0}^{N-1} x[n] \cdot e^{-i \frac{2\pi}{N} kn}, \quad k = 0, 1, \ldots, N-1
$$

---

*本文档由 md-glance 渲染能力测试生成，涵盖 Mermaid 图表 9 种、LaTeX 公式 20+ 组、GFM 扩展语法全覆盖。*
