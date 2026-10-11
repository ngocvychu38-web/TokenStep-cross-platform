#!/bin/bash
set -euo pipefail
# Public client configuration only; device credentials are enrolled separately.
defaults write com.huangshu.TokenStep TokenStep.Supabase.URL -string 'https://hdizeqfyrdfbqohrnuzt.supabase.co'
defaults write com.huangshu.TokenStep TokenStep.Supabase.PublishableKey -string 'sb_publishable_uk6GCUIH9eF8AZjMe-94ww_5j2mIOPS'
echo '已设置现有 Supabase 的公开连接参数。请打开 TokenStep 并登录；新设备还需单独注册采集代理。'
