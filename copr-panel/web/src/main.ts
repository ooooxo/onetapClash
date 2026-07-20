import { createApp } from 'vue'
import './styles/tokens.css'
import App from './App.vue'
import { store } from './store'

document.title = `${store.domain} · 节点管理面板`  // 标题跟随实际域名,不写死
createApp(App).mount('#app')
