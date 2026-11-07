#!/usr/bin/env bash
# Adapted from diagnosing-bugs/scripts/hitl-loop.template.sh.
set -euo pipefail
step() {
  printf '\n>>> %s\n' "$1"
  read -r -p '    [Enter when done] ' _
}
capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p '    > ' answer
  printf -v "$var" '%s' "$answer"
}
step '在 Windows 验证副本中关闭主窗口，使其隐藏到托盘。'
capture MENU '右键托盘图标，显示主窗口和退出两项是否完整可见？(y/n)'
capture QUIT '点击退出 SkillDeck 后是否真正退出？(y/n)'
capture ERROR_MSG '如果失败，描述现象；不要提供凭据。(或 none)'
printf '\nMENU=%s\nQUIT=%s\nERROR_MSG=%s\n' "$MENU" "$QUIT" "$ERROR_MSG"
