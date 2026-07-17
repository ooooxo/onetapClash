import { reactive } from 'vue'

// 全局 UI 状态:哪个 modal/drawer 开着 + toast 队列
export const ui = reactive({
  nodeOpen: false,
  memberEditName: undefined as string | undefined, // undefined=关, ''=新建, 'jf'=编辑
  bulkOpen: false,
  drawerName: undefined as string | undefined,
  toasts: [] as { id: number; msg: string }[],
})

let tid = 0
export function toast(msg: string) {
  const id = ++tid
  ui.toasts.push({ id, msg })
  window.setTimeout(() => {
    const i = ui.toasts.findIndex(t => t.id === id)
    if (i >= 0) ui.toasts.splice(i, 1)
  }, 1800)
}
