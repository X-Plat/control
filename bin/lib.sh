#!/bin/bash
# lib.sh
# ������ά�ӿڵ�ͨ�û����⣬����lib.sh�������ʹ�÷�ͬ�����£����еĸĶ����޸���ά�ӿڣ�ͨ����д������ʵ�֣���Ҫ�޸Ĵ˿⡣
# Ŀǰʹ�ô˽ű�������ģ�飺cb-nginx��cb-fcgi
# ��������ֱ�ӸĶ��˽ű������˽ű������иĶ���Ҫ��֤��������ʹ�ñ��ű�����ά�ӿڣ���

#set -eu
# ������
HOSTNAME=`hostname | awk -F '.' '{print$1"."$2}'`

# ��������Ĭ��ֵΪ��ά�ӿڵ�_controlǰ���֣������������ű�����������������ά�ӿ������¶���
: ${PRO_NAME:=$(basename ${0%%_control})}
# ��ά�ӿ���
: ${CONTROL_NAME:=$(basename ${0})}
# ��������·����Ĭ��Ϊ��ά�ӿ�����·������������ά�ӿڵ�·������������ά�ӿ������¶���
: ${PRO_HOME:="$(pwd)/$(dirname $0)"}
# ��ά�ӿڳ�������·��
: ${MY_PATH:="$PRO_HOME/vendor/control"}
: ${BIN_PATH:="$MY_PATH/bin"}
: ${CONF_PATH:="$MY_PATH/conf"}
: ${DATA_PATH:="$MY_PATH/data"}
: ${LOG_PATH:="$MY_PATH/log"}
: ${LOG_FILE:="$LOG_PATH/control.log"}
# ��־����: fatal 2: warning 3: notice������Խ�ߴ�ӡ�Ķ���Խ��
: ${LOG_LEVEL:=3}
# ����ģ�������ʱ�䣨1s����һ�Σ�
: ${START_WAIT_TIME:=5}
# ֹͣģ�������ʱ�䣨1s����һ�Σ�
: ${STOP_WAIT_TIME:=5}
# try������Ĭ�����Դ���
: ${DEFAULT_TRY_TIME:=3}
# Ĭ���ʼ���������
: ${MAIL_CMD:="/bin/mail"}
# Ĭ�϶��ŷ�������
: ${GSM_CMD:="/bin/gsmsend -s emp01.baidu.com:15003 -s emp02.baidu.com:15003"}
# Ĭ��WGET����
: ${WGET_CMD="wget --limit-rate=5m"}

# �쳣ץȡ
function err_trap()
{
    fatal "[LINE:$1] command or function exited with status $?"
    exit 1
}
trap "err_trap $LINENO" ERR

# �ӿ��������
# ����б�Ľӿڣ���������user_action
function user_action()
{
    return 1
}
function action()
{
    # $1Ϊ������$2Ϊ�����Ĳ���
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

# ��ѯ��ǰ��һЩ��ز�����ʹ��grep��ػ����ļ��ķ�ʽʵ��
function query()
{
    para=${1:-''}
    MONITOR_RESULT_FILE=$DATA_PATH/monitor_result.yaml
    [[ -n $para ]] && grep "$para" $MONITOR_RESULT_FILE || usage

}

# �����������Ҫ�ڰ����мӹ��ܣ���������user_usage����
function user_usage()
{
    return 0
}
function usage()
{
    cat <<-HD_USAGE

${PRO_NAME} ��ά�ӿ�

[�÷�]
$0 action [para]

[�ӿ��б�]
start:       ��������
stop:        ֹͣ����
restart/re:  ��������
monitor/mon: ���ؼ�ؽ��������1����
query/get:   ��ѯ��ؽ���е�ĳЩ��Ŀ��֧�����򣬿��Բ�ѯ����������
status/st:   �����򽡿�״̬
$(user_usage)
other:       ��ӡ�������

HD_USAGE
}

# Ĭ�ϵļ�غ�����ֻ���ý�����飬������д
# ע���ؽ����ʽΪ������Ҫ��BDEOF����
# key:value
function monitor()
{
    ck_health && echo {"status": 0} || echo {"status": 1}
}

# ��ؿ��ƺ���
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

# ������������������д
function start()
{
    cd $PRO_HOME || return 2
    ( ./bin/$PRO_NAME >/dev/null 2>&1 & )
}

# ���򽡿���飬�ᱻ��ͣ�жϵ��ã�������д
function ck_health()
{
    pstree work | grep -v "$CONTROL_NAME" | grep "$PRO_NAME" >/dev/null && return 0 || return 1
}

# ���ؼ����Ľ��
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

# ������飬Ĭ��Ϊ���ý�����飬���������Ҫ�������д
function ck_start()
{
    ck_health && return 0 || return 1
}

# ֹͣ��������������д
function stop()
{
    killall $PRO_NAME || return 0
}

# ������飬Ĭ��Ϊ���ý�����鲢ȡ�������������Ҫ�������д
function ck_stop()
{
    ck_health && return 1 || return 0
}

# �������ԵĻ�������
# $1�����ʹ��eval���ã�������һ�������Ҫ������
# $2�����Դ�����Ĭ��ΪDEFAULT_TRY_TIME
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

# �������ƺ������᳢�Ե���ck_start�ж��Ƿ������ɹ�
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

# ֹͣ���ƺ������᳢�Ե���ck_stop�ж��Ƿ�ֹͣ�ɹ�
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

# ���ʼ��ĺ������л��ռ���Ϊ$MAILLIST���÷�Ϊ
# �ʼ����� | sendmail "�ʼ�����"
# ע���ʼ��������ùܵ������ģ�����
# echo text | sendmail title
function sendmail() {
    $MAIL_CMD -s "$* - from $(hostname)" $MAILLIST
}

# �����ŵĺ������÷�Ϊsendgsm "��������"�������ռ���ΪMOBILELIST
function sendgsm() {
    for mobile in $MOBILELIST
    do
        $GSM_CMD $mobile@"$* - from $(hostname)"
    done
}

# ��ӡ��־��$LOG_PATH/$LOG_FILE
function log() {
    mkdir -p $LOG_PATH
    echo $(date +%F_%T) "$*" | tee -a $LOG_FILE >&2
}

# notice��־
function notice() {
    [[ $LOG_LEVEL -ge 3 ]] && {
        mkdir -p $LOG_PATH
        echo "[NOTICE] $(date +%F_%T) $*" >> $LOG_FILE
    }
}

# warning��־
function warning() {
    [[ $LOG_LEVEL -ge 2 ]] && {
        mkdir -p $LOG_PATH
        echo "[WARNING] $(date +%F_%T) $*" | tee -a $LOG_FILE >&2
    }
}

# fatal��־
function fatal() {
    [[ $LOG_LEVEL -ge 1 ]] && {
        mkdir -p $LOG_PATH
        echo "[FATAL] $(date +%F_%T) $*" | tee -a $LOG_FILE >&2
    }
}

# ������������װ��fatal,sendmail,sendgsm
function alert() {
        fatal "$*"
        echo "$*" | sendmail "$*"
        sendgsm "$*"
}

