# UPMS 接入文档

## 一、后端配置

### 依赖

`pom.xml` 已新增：

```xml
<!-- QSSO 认证 -->
<dependency>
    <groupId>com.qunar.security</groupId>
    <artifactId>qsso-client</artifactId>
    <version>0.0.8</version>
</dependency>
<!-- UPMS 鉴权 -->
<dependency>
    <groupId>com.qunar.tc.upms</groupId>
    <artifactId>tc-upms-auth-client</artifactId>
    <version>1.0.12</version>
</dependency>
```

### 配置

每个 profile 目录下已配置 `qunar-tc-auth.properties`：

| 环境 | 文件 | projectId |
|------|------|-----------|
| local | `profiles/local/qunar-tc-auth.properties` | 1062 |
| betanoah | `profiles/betanoah/qunar-tc-auth.properties` | 1062 |
| prod | `profiles/prod/qunar-tc-auth.properties` | 1128 |
| simulation | `profiles/simulation/qunar-tc-auth.properties` | 1128 |

```properties
common.projectId={环境对应ID}

qsso.authn.url=/api/**

qsso.custom.userInfoProvider=com.qunar.ug.flight.contact.odin.server.infra.auth.OdinCustomAuthUserInfoProvider

upms.authz.url=/api/**
```

### UserInfoProvider

`OdinCustomAuthUserInfoProvider` 从 `upms_login_user` cookie 中提取 userId，无 cookie 时回退到 `qtalkId` header。

---

## 二、UPMS 资源树

```
ODIN 内容中台
├── 标签管理              (菜单 tag)
│   ├── 可视化配置        (菜单 /tag/visual)
│   ├── 分类管理          (菜单 /tag/category)
│   └── 标签列表          (菜单 /tag/list)
├── 内容管理              (菜单 content)
│   ├── 内容库            (菜单 /content/list)
│   └── 内容详情页        (菜单 /content/detail)
├── 任务管理              (菜单 task)
│   ├── 任务列表          (菜单 /task/list)
│   ├── 新建任务          (菜单 /task/create)
│   └── 任务详情页        (菜单 /task/detail)
└── AI 管理               (菜单 ai)
```

### 角色设计

| 角色 | 权限范围 |
|------|---------|
| **admin** | 全部权限，含增删改等敏感操作 |
| **user** | 查询/列表/详情等只读操作 + 创建/编辑 |

### CSV 导入

`upms-resource.csv` 已按 UPMS 批量导入格式生成，可在 UPMS 后台直接导入。

---

## 三、QSSO 登录流程（前后端交互）

### 3.1 后端提供的接口

| 接口 | 方法 | 用途 |
|------|------|------|
| `/_/upms/qsso/isLogin` | GET | 校验当前是否登录 |
| `/_/upms/qsso/loginHtml` | GET | 获取 QSSO 登录页面 HTML |
| `/_/upms/qsso/login` | POST | QSSO 登录回调地址（由 qsso 库自动调用，接收 token） |
| `/_/upms/qsso/logout` | GET | 退出 QSSO 登录 |

### 3.2 判断登录状态

**方式一：响应拦截器捕获 401**

当用户未登录时，后端返回 HTTP 401：

```json
{
    "message": "用户未登录"
}
```

前端全局响应拦截器检测到 401 后跳转 QSSO 登录。

**方式二：主动调用校验接口**

```http
GET /_/upms/qsso/isLogin
```

响应结果：

```json
// 已登录
{ "status": 0, "message": "已登录", "data": true }

// 未登录
{ "status": 0, "message": "未登录", "data": false }

// 内部异常
{ "status": -1, "message": "判断用户是否登录内部异常", "data": null }
```

### 3.3 跳转 QSSO 登录

**方式一：前端自定义登录页（引入 qsso-auth.js）**

```html
<button id="qsso-login">qsso登录</button>
<script src="https://qsso.corp.qunar.com/lib/qsso-auth.js"></script>
<script>
QSSO.attach('qsso-login', '/_/upms/qsso/login?upmsRedirect=' + encodeURIComponent(location.href));
// 自动跳转（无需用户点击）
document.querySelector("#qsso-login").click();
</script>
```

**方式二：直接调用后端接口（推荐）**

```javascript
// 不能用 ajax，要用页面跳转
window.location.href = '/_/upms/qsso/loginHtml?upmsRedirect=' + encodeURIComponent(window.location.href);
```

`upmsRedirect` 参数用于登录成功后重定向到当前页面。

### 3.4 退出登录

```javascript
window.location.href = '/_/upms/qsso/logout?upmsRedirect=' + encodeURIComponent(首页地址);
```

退出后返回登录按钮页面，再点登录会跳转到 `upmsRedirect` 指定的地址。

---

## 四、前端接入方案

### 改动文件

| 文件 | 改动 |
|------|------|
| `src/api/request.js` | 响应拦截器添加 401 处理，自动跳转 QSSO 登录 |
| `src/layouts/index.jsx` | 页面加载时调用 isLogin 校验，未登录跳转 |
| `src/api/auth.js` | **新增** QSSO 登录相关 API |

### 4.1 request.js — 响应拦截器增加 401 处理

在响应拦截器的 error 分支中，检测 `error.response.status === 401`，自动跳转 QSSO 登录页：

```javascript
// 响应拦截器 error 分支
(error) => {
    if (error.response?.status === 401) {
        // 未登录，跳转 QSSO 登录
        window.location.href = '/_/upms/qsso/loginHtml?upmsRedirect='
            + encodeURIComponent(window.location.href);
        return Promise.reject(new Error('未登录'));
    }
    const msg = error.response?.data?.msg || error.message || '网络错误';
    return Promise.reject(new Error(msg));
}
```

### 4.2 src/api/auth.js — 新增文件

```javascript
import request from './request';

/**
 * 校验当前用户是否已登录
 */
export async function checkIsLogin() {
    try {
        const { data } = await request.get('/_/upms/qsso/isLogin');
        return data === true;
    } catch {
        return false;
    }
}

/**
 * 跳转 QSSO 登录页
 */
export function redirectToLogin() {
    window.location.href = '/_/upms/qsso/loginHtml?upmsRedirect='
        + encodeURIComponent(window.location.href);
}

/**
 * 退出登录
 */
export function logout(redirectUrl) {
    const url = redirectUrl || window.location.origin;
    window.location.href = '/_/upms/qsso/logout?upmsRedirect='
        + encodeURIComponent(url);
}
```

### 4.3 layouts/index.jsx — 添加登录态校验

在 Layout 组件中，页面加载时调用 `checkIsLogin`，未登录则跳转：

```jsx
import { useEffect } from 'react';
import { checkIsLogin, redirectToLogin } from '@/api/auth';

const Layout = ({ children }) => {
    const location = useLocation();
    const [collapsed, setCollapsed] = useState(false);
    const [authChecking, setAuthChecking] = useState(true);

    useEffect(() => {
        checkIsLogin().then(isLogin => {
            if (!isLogin) {
                redirectToLogin();
            } else {
                setAuthChecking(false);
            }
        });
    }, []);

    if (authChecking) return null; // 或 loading 组件

    return (/* 原有 JSX */);
};
```

### FAQ

**Q: 为什么同时用 401 拦截 + isLogin 校验？**
A: 双重保护。401 拦截覆盖所有 API 请求的被动检测；isLogin 校验在页面加载时主动检测，避免页面先渲染再跳转的闪烁。

**Q: 本地开发怎么测试？**
A: local 环境也配置了 QSSO 认证，需要本地启动的 ODIN 后端能访问到 QSSO 服务，或者 Nginx 配置代理。

**Q: 登录后需要刷新页面吗？**
A: QSSO 登录回调后，`upmsRedirect` 会自动跳转回原页面，页面重新加载时会带上 cookie，后续请求自动携带凭证。