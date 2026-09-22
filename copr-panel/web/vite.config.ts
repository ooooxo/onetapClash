import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 本地开发连线上后端(只影响 dev,不影响 build):
//   ssh -N -L 9443:127.0.0.1:443 root@<服务器>        # 先开隧道
//   PANEL_PROXY=https://localhost:9443 npm run dev -- --base /panel/
const target = process.env.PANEL_PROXY
const api = { target, secure: false }   // 隧道另一端是服务器 nginx 的正式证书,对 localhost 不匹配

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: target ? { proxy: { '/panel/api': api, '/panel/conv': api, '/get': api } } : {},
})
