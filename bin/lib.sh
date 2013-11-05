#!/bin/bash
# lib.sh
# 所有运维接口的通用基本库，由于lib.sh会对所有使用方同步更新，所有的改动请修改运维接口，通过重写函数来实现，不要修改此库。
# 目前使用此脚本的线上模块：cb-nginx，cb-fcgi
# ！！请勿直接改动此脚本！！此脚本的所有改动需要保证兼容所有使用本脚本的运维接口！！

#set -eu
# 机器名
HOSTNAME=`hostname | awk -F '.' '{print$1"."$2}'`

# 服务名，默认值为运维接口的_control前部分，依赖于启动脚本的命名，建议在运维接口中重新定义
: ${PRO_NAME:=$(basename ${0%%_control})}
# 运维接口名
: ${CONTROL_NAME:=$(basename ${0})}
# 服务所在路径，默认为运维接口所在路径，依赖于运维接口的路径，建议在运维接口中重新定义
: ${PRO_HOME:="$(pwd)/$(dirname $0)"}
# 运维接口程序的相关路径
: ${MY_PATH:="$PRO_HOME/vendor/control"}
: ${BIN_PATH:="$MY_PATH/bin"}
: ${CONF_PATH:="$MY_PATH/conf"}
: ${DATA_PATH:="$MY_PATH/data"}
: ${LOG_PATH:="$MY_PATH/log"}
: ${LOG_FILE:="$LOG_PATH/control.log"}
# 日志级别: fatal 2: warning 3: notice，级别越高打印的东西越多
: ${LOG_LEVEL:=3}
# 启动模块的重试时间（1s重试一次）
: ${START_WAIT_TIME:=5}
# 停止模块的重试时间（1s重试一次）
: ${STOP_WAIT_TIME:=5}
# try函数的默认重试次数
: ${DEFAULT_TRY_TIME:=3}
# 默认邮件发送命令
: ${MAIL_CMD:="/bin/mail"}
# 默认短信发送命令
: ${GSM_CMD:="/bin/gsmsend -s emp01.baidu.com:15003 -s emp02.baidu.com:15003"}
# 默认WGET命令
: ${WGET_CMD="wget --limit-rate=5m"}

# 异常抓取
function err_trap()
{
    fatal "[LINE:$1] command or function exited with status $?"
    exit 1
}
trap "err_trap $LINENO" ERR

# 接口命令解释
# 如果有别的接口，建议重载user_action
function user_action()
{
    return 1
}
function action()
{
    # $1为动作，$2为动作的参数
    : ${func:=${1:-'other'}}
    shift || true
    : ${para:=${@:-''}}
    user_action && exit 0 || true
    case "$func" in
        start) cmd_start ;;
        stop) cmd_stop ;;
        restart|re) cmd_stop && cmd_start ;;
        mon|monitor) cmd_monitor $para;;
        status|st) ck_status ;;
        query|get) query $para ;;
        *) usage ;;
    esac
}

# 查询当前的一些监控参数，使用grep监控缓存文件的方式实现
function query()
{
    para=${1:-''}
    MONITOR_RESULT_FILE=$DATA_PATH/monitor_result.yaml
    [[ -n $para ]] && grep "$para" $MONITOR_RESULT_FILE || usage

}

# 帮助，如果需要在帮助中加功能，可以重载user_usage函数
function user_usage()
{
    return 0
}
function usage()
{
    cat <<-HD_USAGE

${PRO_NAME} 运维接口

[用法]
$0 action [para]

[接口列表]
start:       启动程序
stop:        停止程序
restart/re:  重启程序
monitor/mon: 返回监控结果，缓存1分钟
query/get:   查询监控结果中的某些项目，支持正则，可以查询的内容如下
status/st:   检查程序健康状态
$(user_usage)
other:       打印这个帮助

HD_USAGE
}

# 默认的监控函数，只调用健康检查，建议重写
# 注意监控结果格式为（不需要打BDEOF）：
# key:value
function monitor()
{
    ck_health && echo {"status": 0} || echo {"status": 1}
}

# 监控控制函数
function cmd_monitor()
{
    MONITOR_RESULT_FILE=$DATA_PATH/monitor_result
    
    monitor > $MONITOR_RESULT_FILE.json.tmp

    mv $MONITOR_RESULT_FILE.json.tmp $MONITOR_RESULT_FILE.json
    $BIN_PATH/conv -f json -t json $MONITOR_RESULT_FILE.json > $MONITOR_RESULT_FILE.json.tmp 2>/dev/null
    mv $MONITOR_RESULT_FILE.json.tmp $MONITOR_RESULT_FILE.json
    $BIN_PATH/conv -f json -t yaml $MONITOR_RESULT_FILE.json > $MONITOR_RESULT_FILE.yaml.tmp 2>/dev/null
    mv $MONITOR_RESULT_FILE.yaml.tmp $MONITOR_RESULT_FILE.yaml

    [[ "$para" == json ]] && cat $MONITOR_RESULT_FILE.json || cat $MONITOR_RESULT_FILE.yaml

}

# 启动程序的命令，建议重写
function start()
{
    cd $PRO_HOME || return 2
    ( ./bin/$PRO_NAME >/dev/null 2>&1 & )
}

# 程序健康检查，会被启停判断调用，建议重写
function ck_health()
{
    pstree work | grep -v "$CONTROL_NAME" | grep "$PRO_NAME" >/dev/null && return 0 || return 1
}

# 返回检查检查的结果
function ck_status()
{
    ck_health && {
        echo status: OK
        return 0
    } || {
        echo status: ERROR
        return 1
    }
}

# 启动检查，默认为调用健康检查，如果有特殊要求可以重写
function ck_start()
{
    ck_health && return 0 || return 1
}

# 停止程序的命令，建议重写
function stop()
{
    killall $PRO_NAME || return 0
}

# 启动检查，默认为调用健康检查并取反，如果有特殊要求可以重写
function ck_stop()
{
    ck_health && return 1 || return 0
}

# 用于重试的基本函数
# $1：命令，使用eval调用，可以是一串命令，需要用引号
# $2：重试次数，默认为DEFAULT_TRY_TIME
function try()
{
    cmd2try=$1
    total_try_time=${2:$DEFAULT_TRY_TIME}
    tryed=1

    notice "try $cmd2try ($tryed)"
    eval $cmd2try && {
        notice "$cmd2try success ($tryed) !"
        return 0
    } || {
        notice "$cmd2try fail ($tryed)."
    }
    while [[ $tryed -lt $total_try_time ]]
    do
        ((tryed++))
        notice "try $cmd2try ($tryed)"
        eval $cmd2try && {
            notice "$cmd2try success !"
            return 0
        } || {
            notice "$cmd2try fail ($tryed)."
        }
        sleep 1
    done
    warning "$cmd2try finally failed !"
    return 1
}

# 启动控制函数，会尝试调用ck_start判断是否启动成功
function cmd_start()
{
    ck_start && {
        notice "$PRO_NAME already started !"
        echo "$PRO_NAME already started !"
        return 0
    }
    notice "try to start $PRO_NAME"
    start
    wait_s=0
    success=1
    ck_start && success=0
    while [[ $success -ne 0 && $wait_s -lt $START_WAIT_TIME ]]
    do
            ((wait_s++))
            sleep 1
            ck_start && success=0
    done
    [[ $success -eq 0 ]] && {
        notice "$PRO_NAME start success !"
        echo "$PRO_NAME start success !"
    } || {
        warning "$PRO_NAME start fail !"
        exit 1
    }
}

# 停止控制函数，会尝试调用ck_stop判断是否停止成功
function cmd_stop()
{
    ck_stop && {
        notice "$PRO_NAME already stoped !"
        echo "$PRO_NAME already stoped !"
        return 0
    }
    notice "try to stop $PRO_NAME"
    stop
    wait_s=0
    success=1
    ck_stop && success=0
    while [[ $success -ne 0 && $wait_s -lt $STOP_WAIT_TIME ]]
    do
            ((wait_s++))
            sleep 1
            ck_stop && success=0
    done
    [[ $success -eq 0 ]] && {
        notice "$PRO_NAME stop success !"
        echo "$PRO_NAME stop success !"
    } || {
        warning "$PRO_NAME stop fail !"
        exit 1
    }
}

# 发邮件的函数，有机收件人为$MAILLIST，用法为
# 邮件正文 | sendmail "邮件标题"
# 注意邮件正文是用管道给出的，比如
# echo text | sendmail title
function sendmail() {
    $MAIL_CMD -s "$* - from $(hostname)" $MAILLIST
}

# 发短信的函数，用法为sendgsm "短信内容"，短信收件人为MOBILELIST
function sendgsm() {
    for mobile in $MOBILELIST
    do
        $GSM_CMD $mobile@"$* - from $(hostname)"
    done
}

# 打印日志到$LOG_PATH/$LOG_FILE
function log() {
    mkdir -p $LOG_PATH
    echo $(date +%F_%T) "$*" | tee -a $LOG_FILE >&2
}

# notice日志
function notice() {
    [[ $LOG_LEVEL -ge 3 ]] && {
        mkdir -p $LOG_PATH
        echo "[NOTICE] $(date +%F_%T) $*" >> $LOG_FILE
    }
}

# warning日志
function warning() {
    [[ $LOG_LEVEL -ge 2 ]] && {
        mkdir -p $LOG_PATH
        echo "[WARNING] $(date +%F_%T) $*" | tee -a $LOG_FILE >&2
    }
}

# fatal日志
function fatal() {
    [[ $LOG_LEVEL -ge 1 ]] && {
        mkdir -p $LOG_PATH
        echo "[FATAL] $(date +%F_%T) $*" | tee -a $LOG_FILE >&2
    }
}

# 报警函数，包装了fatal,sendmail,sendgsm
function alert() {
        fatal "$*"
        echo "$*" | sendmail "$*"
        sendgsm "$*"
}

