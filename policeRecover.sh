#!/bin/bash
#author: 黄高明
#date: 2018-01-09
#weixin:NelsonWinner
#结合ZABBIX故障自愈  
logdir=/data/log/shell          #日志路径
log=$logdir/police.log            #日志文件
is_font=1                #终端是否打印日志: 1打印 0不打印
is_log=0                #是否记录日志: 1记录 0不记录
basePath=$(cd "$(dirname "$0")"; pwd)
commonConf="${basePath}/common.config"
ruleConf="${basePath}/rule.config"
tempDir="${basePath}/temp"
bashVersion=$(bash --version |grep 'version' |grep 'bash' |awk -F'version' '{print $2}' |awk -F'-' '{print $1}')
bashVerNumber=$( echo "${bashVersion}" |awk -F'.' '{print $1}')
checkBin=("bc" "curl" "expr" "telnet" "expect" "sshpass")
source /etc/profile

#动态时间
datef(){
    date "+%Y-%m-%d %H:%M:%S"
}

#输出日志
print_log(){
    if [[ $is_log -eq 1  ]];then
        [[ -d $logdir ]] || mkdir -p $logdir
        if [[ $2 != "" ]]; then
            echo -e "[ $(datef) ] $2 $1" >> $log
        else
            echo -e "[ $(datef) ] $1" >> $log
        fi
        
    fi
    if [[ $is_font -eq 1  ]];then
        if [[ $2 != "" && $3 = "" ]]; then
            echo -e "[ $(datef) ] $2 $1"
        elif [[ $3 != "" ]]; then
            color=$3
            echo -e "[ $(datef) ] \033[${color}m$2 $1\033[0m"
        else
            echo -e "[ $(datef) ] $1"
        fi        
    fi
}

#检查系统
checkSyshell(){
    if [[ ${bashVerNumber} -lt 4  ]]; then
        print_log "bash版本必须大于或等于4.x.x,当前版本:${bashVersion}" "[ERROR] ${FUNCNAME} - " "31" ; exit
    fi
    for (( i = 0; i < ${#checkBin[*]}; i++ )); do
        which ${checkBin[$i]} &> /dev/null  
        if [[ $? -ne 0 ]]; then
            print_log "系统中没有:${checkBin[$i]}命令,请先安装后执行" "[ERROR] ${FUNCNAME} - " "31" ; exit
        fi
    done
}

if [[ ! -f ${commonConf} ]]; then
    print_log "基础配置文件:${commonConf}不存在" "[ERROR] ${FUNCNAME} - " "31" ; exit
fi
if [[ ! -f ${ruleConf} ]]; then
   print_log "规则配置文件:${ruleConf}不存在" "[ERROR] ${FUNCNAME} - " "31";exit
fi
if [[ ! -d ${tempDir} ]]; then
    mkdir -p ${tempDir}
fi

#获取salt Token
getsaltToken(){
    saltUrl="$1"
    local saltUsername="$2"
    local saltPassword="$3"
    if [[ "${saltUrl}" == "" ]]; then
        print_log "saltUrl不能为空" "[ERROR] ${FUNCNAME} - " "31";exit
    fi
    if [[ "${saltUsername}" == "" ]]; then
        print_log "saltUsername不能为空" "[ERROR] ${FUNCNAME} - " "31";exit
    fi
    if [[ "${saltPassword}" == "" ]]; then
        print_log "saltPassword不能为空" "[ERROR] ${FUNCNAME} - " "31";exit
    fi
    saltoken=$(curl -s -k "${saltUrl}/login" -H "Accept: application/x-yaml" -d username="${saltUsername}" -d password="${saltPassword}" -d eauth="pam" |grep "token" |awk -F':' '{print $2}')
    if [[ "${saltoken}" == "" ]]; then
        print_log "获取salt Token为空,退出" "[ERROR] ${FUNCNAME} - " "31";exit
    else
        print_log "获取salt Token:${saltoken}" "[INFO] ${FUNCNAME} -  "
    fi
}

#执行salt任务
runsaltTask(){
    local target="$1"
    local cmd="$2"
    local mtimeout="$3"
    local tempfile="$4"
    local lockFile="$5"
    local start
    local end
    local httpRret
    if [[ "${saltoken}" == "" ]]; then
        print_log "获取salt Token为空,请注意执行顺序是否正确,退出" "[ERROR] ${FUNCNAME} - " "31";exit
    fi
    if [[ "${target}" == "" ]]; then
        print_log "获取执行target为空,退出" "[ERROR] ${FUNCNAME} - " "31";exit
    fi
    if [[ "${cmd}" == "" ]]; then
        print_log "获取cmd为空,退出" "[ERROR] ${FUNCNAME} - " "31";exit
    fi
    if [[ "${mtimeout}" == "" ]]; then
        print_log "请求超时不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${tempfile}" == "" ]]; then
        print_log "请求保存文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${lockFile}" == "" ]]; then
        print_log "请求锁文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ -f ${lockFile} ]]; then
        lockinfo=$(cat ${lockFile})
        print_log "请求锁已经存在,执行进程已经在运行,退出请求操作.\n${lockinfo}" "[ERROR] ${FUNCNAME} - " "31"
        exit
    else
        echo "请求远程执行命令" > ${lockFile}
        echo "开始时间: $(datef)" >> ${lockFile}
        echo "请求url: $saltUrl" >> ${lockFile}
        echo "请求参数:\n${cmd}" >> ${lockFile}
        echo "超时时间:${mtimeout}" >> ${lockFile}
        echo "保存文件:${tempfile}" >> ${lockFile}    
    fi
    echo "curl -k -s \"${saltUrl}/\" -H \"Accept: application/x-yaml\" -H \"X-Auth-Token: ${saltoken}\" -d client=\"local\" -d tgt=\"${target}\" -d fun=\"cmd.run\" -d arg=\"${cmd}\"  -m ${mtimeout} -o ${tempfile} -w %{http_code}" > ${tempDir}/curl_${eventId}.sh
    print_log "请求url: ${saltUrl}" "[INFO] ${FUNCNAME} -  "
    print_log "请求参数:\n${cmd}" "[INFO] ${FUNCNAME} -  "
    print_log "执行主机:${host}" "[INFO] ${FUNCNAME} -  "
    print_log "超时时间:${mtimeout}" "[INFO] ${FUNCNAME} -  "
    print_log "保存文件:${tempfile}" "[INFO] ${FUNCNAME} -  "
    start=$(date "+%s")
    http_code=$(curl -k -s "${saltUrl}/" -H "Accept: application/x-yaml" -H "X-Auth-Token: ${saltoken}" -d client="local" -d tgt="${target}" -d fun="cmd.run" -d arg="${cmd}"  -m ${mtimeout} -o ${tempfile} -w %{http_code}) 
    httpRret=$?
    if [[ -f ${lockFile} ]]; then
        rm -f ${lockFile}
    fi
    if [[ ${httpRret} -ne 0 ]]; then
        if [[ ! -f  ${tempfile} ]]; then
            print_log "执行curl命令失败,未形成curl文件,请检查curl参数" "[ERROR] ${FUNCNAME} - " "31"
            exit
        fi   
        
    fi
    stdout=$(cat ${tempfile}|grep -v "return")
    stderr=""
    end=$(date "+%s")
    take=$(expr $end - $start) 
    if [[ "${stdout}"  = "" ]]; then
        print_log "执行curl salt-api的返回内容为空,请检查" "[ERROR] ${FUNCNAME} - " "31"
    fi   
    print_log "请求返回结果,返回码:${http_code} 花费时间:${take}秒" "[INFO] ${FUNCNAME} -  "
    print_log "标准输出: \n${stdout}" "[INFO] ${FUNCNAME} -  "

}

#exect执行
expectRun()
{
    local User=$1
    local Password=$2
    local Host=$3
    local Cmd=$4
    local connectTimeout=$5
    if [[ "${User}"  = ""  ]] ;then print_log "ssh用户名不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Password}"  = ""  ]] ;then print_log "ssh用户密码不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Host}"  = ""  ]] ;then print_log "ssh主机不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Cmd}"  = ""  ]] ;then print_log "ssh执行命令不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${connectTimeout}"  = ""  ]] ;then print_log "ssh超时时间不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    expect -c "
            spawn /usr/bin/ssh -o StrictHostKeyChecking=no  $User@$Host
            set timeout ${connectTimeout}
            expect \"\*password\*:\"
            send \"${Password}\r\"
            expect \"\*\>\"
            send \"${Cmd} \r\"
            expect \"\*\>\"
            send \"exit\r\"
            expect eof 
              "
}

#免秘钥ssh执行
keyLessRun(){
    local User=$1
    local Host=$2
    local Cmd=$3
    local connectTimeout=$4
    local tempfile=$5
    local lockFile=$6
    local start
    local end
    local lockinfo  
    local runres  
    local runret  
    if [[ "${User}"  = ""  ]] ;then print_log "ssh用户名不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Host}"  = ""  ]] ;then print_log "ssh主机不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Cmd}"  = ""  ]] ;then print_log "ssh执行命令不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${connectTimeout}"  = ""  ]] ;then print_log "ssh超时时间不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${tempfile}" == "" ]]; then
        print_log "请求保存文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${lockFile}" == "" ]]; then
        print_log "请求锁文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ -f ${lockFile} ]]; then
        lockinfo=$(cat ${lockFile})
        print_log "请求锁已经存在,执行进程已经在运行,退出请求操作.\n${lockinfo}" "[ERROR] ${FUNCNAME} - " "31"
        exit
    else
        echo "请求远程执行命令" > ${lockFile}
        echo "开始时间: $(datef)" >> ${lockFile}
        echo "请求方式: 免秘钥ssh执行" >> ${lockFile}
        echo "请求参数:\n${cmd}" >> ${lockFile}
        echo "超时时间:${connectTimeout}" >> ${lockFile}
        echo "保存文件:${tempfile}" >> ${lockFile}    
    fi
    print_log "开始使用expect校验${Host}是否添加无秘钥认证" "[INFO] ${FUNCNAME} -  "
    checkeyLessRes=$(expectRun "${User}" "id" "${Host}" "id" "10")
    if [[ -z ` echo "${checkeyLessRes}" |grep "Permission" ` ]];then
        print_log "${Host}启用了无秘钥认证" "[INFO] ${FUNCNAME} -  "
    else
        if [[ -f ${lockFile} ]]; then
            rm -f ${lockFile}
        fi
        print_log "${Host}没有启用了无秘钥认证" "[ERROR] ${FUNCNAME} -" "31" ;exit 
    fi

    echo "ssh ${User}@${Host} -o StrictHostKeyChecking=no   -o ConnectTimeout=${connectTimeout} \"${Cmd}\" " > ${tempDir}/curl_${eventId}.sh
    print_log "请求方式: 免秘钥ssh执行" "[INFO] ${FUNCNAME} -  "
    print_log "请求参数:\n${Cmd}" "[INFO] ${FUNCNAME} -  "
    print_log "执行主机:${host}" "[INFO] ${FUNCNAME} -  "
    print_log "超时时间:${connectTimeout}" "[INFO] ${FUNCNAME} -  "
    print_log "保存文件:${tempfile}" "[INFO] ${FUNCNAME} -  "
    start=$(date "+%s")
    runres=$(ssh ${User}@${Host} -o StrictHostKeyChecking=no   -o ConnectTimeout=${connectTimeout} "${Cmd}"  >${tempfile})
    runret=$?
    http_code=${runret}
    if [[ -f ${lockFile} ]]; then
        rm -f ${lockFile}
    fi
    if [[ ${runret} -ne 0 ]]; then
        if [[ ! -f  ${tempfile} ]]; then
            print_log "执行ssh免秘钥命令失败,未形成结果文件,请检查参数" "[ERROR] ${FUNCNAME} - " "31"
            exit
        fi   
        
    fi
    stdout=$(cat ${tempfile}|grep -v "return")
    stderr=""
    end=$(date "+%s")
    take=$(expr $end - $start) 
    if [[ "${stdout}"  = "" ]]; then
        print_log "执行ssh免秘钥命令的返回内容为空,请检查" "[ERROR] ${FUNCNAME} - " "31"
    fi   
    print_log "请求返回结果,返回状态:${http_code} 花费时间:${take}秒" "[INFO] ${FUNCNAME} -  "
    print_log "标准输出: \n${stdout}" "[INFO] ${FUNCNAME} -  "
}

#expect ssh执行
sshExpectRun(){
    local User=$1
    local Host=$2
    local Cmd=$3
    local connectTimeout=$4
    local tempfile=$5
    local lockFile=$6
    local password=$7
    local start
    local end
    local lockinfo  
    local runres  
    local runret  
    if [[ "${User}"  = ""  ]] ;then print_log "ssh用户名不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${password}"  = ""  ]] ;then print_log "ssh用户密码不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Host}"  = ""  ]] ;then print_log "ssh主机不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Cmd}"  = ""  ]] ;then print_log "ssh执行命令不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${connectTimeout}"  = ""  ]] ;then print_log "ssh超时时间不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${tempfile}" == "" ]]; then
        print_log "请求保存文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${lockFile}" == "" ]]; then
        print_log "请求锁文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ -f ${lockFile} ]]; then
        lockinfo=$(cat ${lockFile})
        print_log "请求锁已经存在,执行进程已经在运行,退出请求操作.\n${lockinfo}" "[ERROR] ${FUNCNAME} - " "31"
        exit
    else
        echo "请求远程执行命令" > ${lockFile}
        echo "开始时间: $(datef)" >> ${lockFile}
        echo "请求方式: expect ssh执行" >> ${lockFile}
        echo "请求参数:\n${cmd}" >> ${lockFile}
        echo "超时时间:${connectTimeout}" >> ${lockFile}
        echo "保存文件:${tempfile}" >> ${lockFile}    
    fi


    echo "expect \"${User}\" \"${password}\" \"${Host}\" \"${Cmd}\"  \"${connectTimeout}\"  " > ${tempDir}/curl_${eventId}.sh
    print_log "请求方式: ssh expect执行" "[INFO] ${FUNCNAME} -  "
    print_log "请求参数:\n${Cmd}" "[INFO] ${FUNCNAME} -  "
    print_log "执行主机:${host}" "[INFO] ${FUNCNAME} -  "
    print_log "超时时间:${connectTimeout}" "[INFO] ${FUNCNAME} -  "
    print_log "保存文件:${tempfile}" "[INFO] ${FUNCNAME} -  "
    start=$(date "+%s")
    print_log "开始同步执行expect命令" "[INFO] ${FUNCNAME} -  "
    runres=$(expectRun "${User}" "${password}" "${Host}" "${Cmd}"  "${connectTimeout}" >${tempfile})
    runret=$?
    http_code=${runret}
    if [[ -f ${lockFile} ]]; then
        rm -f ${lockFile}
    fi
    if [[ ${runret} -ne 0 ]]; then
        if [[ ! -f  ${tempfile} ]]; then
            print_log "执行ssh expect命令失败,未形成结果文件,请检查参数" "[ERROR] ${FUNCNAME} - " "31"
            exit
        fi   
        
    fi
    stdout=$(cat ${tempfile}|grep -v "return")
    stderr=""
    end=$(date "+%s")
    take=$(expr $end - $start) 
    if [[ "${stdout}"  = "" ]]; then
        print_log "执行ssh expect命令的返回内容为空,请检查" "[ERROR] ${FUNCNAME} - " "31"
    fi   
    print_log "请求返回结果,返回状态:${http_code} 花费时间:${take}秒" "[INFO] ${FUNCNAME} -  "
    print_log "标准输出: \n${stdout}" "[INFO] ${FUNCNAME} -  "
}

#ansible远程执行
ansibleRun(){
    local Host=$1
    local Cmd=$2
    local connectTimeout=$3
    local tempfile=$4
    local lockFile=$5
    local start
    local end
    local lockinfo  
    local runres  
    local runret  
    if [[ "${Host}"  = ""  ]] ;then print_log "ssh主机不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Cmd}"  = ""  ]] ;then print_log "ssh执行命令不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${connectTimeout}"  = ""  ]] ;then print_log "ssh超时时间不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${tempfile}" == "" ]]; then
        print_log "请求保存文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${lockFile}" == "" ]]; then
        print_log "请求锁文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ -f ${lockFile} ]]; then
        lockinfo=$(cat ${lockFile})
        print_log "请求锁已经存在,执行进程已经在运行,退出请求操作.\n${lockinfo}" "[ERROR] ${FUNCNAME} - " "31"
        exit
    else
        echo "请求远程执行命令" > ${lockFile}
        echo "开始时间: $(datef)" >> ${lockFile}
        echo "请求方式: ansible远程执行" >> ${lockFile}
        echo "请求参数:\n${Cmd}" >> ${lockFile}
        echo "超时时间:${connectTimeout}" >> ${lockFile}
        echo "保存文件:${tempfile}" >> ${lockFile}    
    fi
    echo "ansible \"${Host}\" -m command -a \"${Cmd}\" --timeout=\"${connectTimeout}\"" > ${tempDir}/curl_${eventId}.sh
    print_log "请求方式: ansible远程执行" "[INFO] ${FUNCNAME} -  "
    print_log "请求参数:\n${Cmd}" "[INFO] ${FUNCNAME} -  "
    print_log "执行主机:${host}" "[INFO] ${FUNCNAME} -  "
    print_log "超时时间:${connectTimeout}" "[INFO] ${FUNCNAME} -  "
    print_log "保存文件:${tempfile}" "[INFO] ${FUNCNAME} -  "
    start=$(date "+%s")
    runres=$(ansible  "${Host}" -m raw -a "${Cmd}" --timeout="${connectTimeout}">${tempfile})
    runret=$?
    http_code=${runret}
    if [[ -f ${lockFile} ]]; then
        rm -f ${lockFile}
    fi
    if [[ ${runret} -ne 0 ]]; then
        if [[ ! -f  ${tempfile} ]]; then
            print_log "ansible远程执行命令失败,未形成结果文件,请检查参数" "[ERROR] ${FUNCNAME} - " "31"
            exit
        fi   
        
    fi
    stdout=$(cat ${tempfile}|grep -v "success")
    stderr=""
    end=$(date "+%s")
    take=$(expr $end - $start) 
    if [[ "${stdout}"  = "" ]]; then
        print_log "ansible远程执行命令的返回内容为空,请检查" "[ERROR] ${FUNCNAME} - " "31"
    fi   
    print_log "请求返回结果,返回状态:${http_code} 花费时间:${take}秒" "[INFO] ${FUNCNAME} -  "
    print_log "标准输出: \n${stdout}" "[INFO] ${FUNCNAME} -  "
}

#sshpass远程执行
sshPassRun(){
    local User=$1
    local Host=$2
    local Cmd=$3
    local connectTimeout=$4
    local tempfile=$5
    local lockFile=$6
    local password=$7
    local start
    local end
    local lockinfo  
    local runres  
    local runret  
    if [[ "${User}"  = ""  ]] ;then print_log "ssh用户名不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${password}"  = ""  ]] ;then print_log "ssh用户密码不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Host}"  = ""  ]] ;then print_log "ssh主机不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${Cmd}"  = ""  ]] ;then print_log "ssh执行命令不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${connectTimeout}"  = ""  ]] ;then print_log "ssh超时时间不能为空" "[ERROR] ${FUNCNAME} - " "31" ;exit ;fi
    if [[ "${tempfile}" == "" ]]; then
        print_log "请求保存文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${lockFile}" == "" ]]; then
        print_log "请求锁文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ -f ${lockFile} ]]; then
        lockinfo=$(cat ${lockFile})
        print_log "请求锁已经存在,执行进程已经在运行,退出请求操作.\n${lockinfo}" "[ERROR] ${FUNCNAME} - " "31"
        exit
    else
        echo "请求远程执行命令" > ${lockFile}
        echo "开始时间: $(datef)" >> ${lockFile}
        echo "请求方式: sshpass执行" >> ${lockFile}
        echo "请求参数:\n${cmd}" >> ${lockFile}
        echo "超时时间:${connectTimeout}" >> ${lockFile}
        echo "保存文件:${tempfile}" >> ${lockFile}    
    fi

    # 
    echo "sshpass -p \"${password}\" ssh ${User}@${Host} -o StrictHostKeyChecking=no   -o ConnectTimeout=\"${connectTimeout}\" \"${Cmd}\"" > ${tempDir}/curl_${eventId}.sh
    print_log "请求方式: sshpass执行" "[INFO] ${FUNCNAME} -  "
    print_log "请求参数:\n${Cmd}" "[INFO] ${FUNCNAME} -  "
    print_log "执行主机:${host}" "[INFO] ${FUNCNAME} -  "
    print_log "超时时间:${connectTimeout}" "[INFO] ${FUNCNAME} -  "
    print_log "保存文件:${tempfile}" "[INFO] ${FUNCNAME} -  "
    start=$(date "+%s")
    print_log "开始同步执行sshpass命令" "[INFO] ${FUNCNAME} -  "
    runres=$(sshpass -p "${password}" ssh ${User}@${Host} -o StrictHostKeyChecking=no   -o ConnectTimeout="${connectTimeout}" "${Cmd}" >${tempfile})
    runret=$?
    http_code=${runret}
    if [[ -f ${lockFile} ]]; then
        rm -f ${lockFile}
    fi
    if [[ ${runret} -ne 0 ]]; then
        if [[ ! -f  ${tempfile} ]]; then
            print_log "执行sshpass命令失败,未形成结果文件,请检查参数" "[ERROR] ${FUNCNAME} - " "31"
            exit
        fi   
        
    fi
    stdout=$(cat ${tempfile}|grep -v "return")
    stderr=""
    end=$(date "+%s")
    take=$(expr $end - $start) 
    if [[ "${stdout}"  = "" ]]; then
        print_log "执行sshpass命令的返回内容为空,请检查" "[ERROR] ${FUNCNAME} - " "31"
    fi   
    print_log "请求返回结果,返回状态:${http_code} 花费时间:${take}秒" "[INFO] ${FUNCNAME} -  "
    print_log "标准输出: \n${stdout}" "[INFO] ${FUNCNAME} -  "
}

#发送邮件
sendMail(){
        export LANG="zh_CN.UTF-8"
        local smtp="${smtp}" # 邮件服务器地址+25端口
        local smtp_domain="${smtpDomain}" # 发送邮件的域名，即@后面的
        local FROM="${from}" # 发送邮件地址        
        local username_base64="${usernameBase64}" # 用户名base64编码
        local password_base64="${passwordBase64}" # 密码base64编码
        local RCPTTO="${toEmail}" # 收件人地址
        local Subject=$1
        local data=$2
        local user
        Subject=$(echo "${Subject}"|xargs  |base64 |tr "\n" "-")
        Subject="?UTF-8?B?${Subject}?=\nContent-Type: text/plain;\n    charset=\"UTF-8\"\nContent-Transfer-Encoding: base64"
        data=$(echo -e  "${data}"|base64)
        if [[ "${RCPTTO}" == "" ]]; then
            print_log "收件人地址不能为空" "[ERROR] ${FUNCNAME} - " "31"
            return 2
        fi
        if [[ "${Subject}" == "" ]]; then
            print_log "邮件主题不能为空" "[ERROR] ${FUNCNAME} - " "31"
            return 2
        fi
        if [[ "${data}" == "" ]]; then
            print_log "邮件内容不能为空" "[ERROR] ${FUNCNAME} - " "31"
            return 2
        fi
        print_log "base64邮件主题:${Subject}" "[INFO] ${FUNCNAME} - "
        print_log "base64邮件内容:${data}" "[INFO] ${FUNCNAME} - "
        for user in `echo "${RCPTTO}" |tr " " "\n" |grep -v "^$"`
        do
            print_log "${user}:开始发送邮件" "[INFO] ${FUNCNAME} - "
            ( for i in "ehlo $smtp_domain" "AUTH LOGIN" "$username_base64" "$password_base64" "MAIL FROM:<$FROM>" "RCPT TO:<${user}>" "DATA";do
                    echo $i
                    sleep  2
            done
            echo -e "Subject: =${Subject}"
            echo -e "${data}"
            echo "."
            sleep 1
            echo "quit" )|telnet $smtp  > ${tempDir}/smtp.txt
            local ret=$?
            print_log "返回值:${ret}"
            if [[ ! -f ${tempDir}/smtp.txt  ]]; then
                print_log "${user}:邮件命令执行失败" "[ERROR] ${FUNCNAME} - " "31"
            else
                local smtpRes=$(cat ${tempDir}/smtp.txt)
                if [[ ! -z ` echo "${smtpRes}"| grep "queued"` ]]; then
                    print_log "${user}:邮件发送成功" "[INFO ]"
                else
                    print_log "${user}:邮件发送失败" "[ERROR] ${FUNCNAME} - " "31"
                    print_log "邮件日志:\n${smtpRes}"
                fi
            fi

        done

}

#构造微信消息体
makeBody() {
        local int AppID=${AppID}
        local UserID
        local PartyID
        if [[ ${isSendAll} -eq 0 ]]; then
            UserID=$(echo "${sendUsers[*]}"|sed "s/ / \| /g")
        else
            UserID=@all
            PartyID=${PartyID}
        fi
        local Msg=$(echo -e "$1")
        printf '{\n'
        printf '\t"touser": "'"$UserID"\"",\n"
        printf '\t"toparty": "'"$PartyID"\"",\n"
        printf '\t"msgtype": "text",\n'
        printf '\t"agentid": "'" $AppID "\"",\n"
        printf '\t"text": {\n'
        printf '\t\t"content": "'"$Msg"\""\n"
        printf '\t},\n'
        printf '\t"safe":"0"\n'
        printf '}\n'
}

#微信消息
sendWeixin(){
    export LANG=en_US.UTF-8
    local message=$1
    local ret
    if [[ ${message}  == "" ]]; then
        print_log "微信消息内容不能为空" "[ERROR] ${FUNCNAME} - " "31"
        return 77
    fi    
    GURL="https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=$CropID&corpsecret=$Secret"
    Gtoken=$(curl -k -s -G $GURL | awk -F\" '{print $10}')
    if [[ "${Gtoken}"  == "" ]];then
        print_log "获取微信Token:${Gtoken}为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        return 78
    else
        print_log "获取微信Token:${Gtoken}" "[INFO] ${FUNCNAME} - "
    fi
    PURL="https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=$Gtoken" 
    curlRes=$(curl -k -H "charset=UTF-8"  --data-ascii "$(makeBody "${message}")" $PURL)   
    ret=$?
    if [[ ${ret} -ne 0  ]]; then
        print_log "执行curl消息失败" "[ERROR] ${FUNCNAME} - " "31"
        return 88
    fi
    print_log "执行Curl消息成功,返回结果:`echo -e "${curlRes}"`" "[INFO] ${FUNCNAME} -  "
}

#解析第一个参数,返回数组内容
dealFirstParams(){
    local data
    firstParmas=$1
    if [[ ${firstParmas}  == "" ]]; then
        print_log "参数不能为空,退出告警自动恢复" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    data=$(echo "${firstParmas}" |awk -F'#' '{print $1}' |sed "s/_/ /")
    echo "${data}"
}
#校验第1个参数
firstCheck(){
    local data=($1)
    if [[ ${#data[*]} -ne 2 ]]; then
        print_log "解析第1个参数,返回第1个参数的个数不为2:${#data[*]}" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    eventId=${data[0]}
    triggerValue=${data[1]}
    expr $eventId "+" 10 &> /dev/null  
    if [ $? -ne 0 ];then   
        print_log "eventid: ${eventId} 不是一个整数的数字,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit  
    fi  
    if [[ $triggerValue -ne 1 ]]; then
        print_log "triggervalue: ${triggerValue} 不等于1(故障消息),退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi    
}
#解析第2个参数,返回字典内容
dealSecondParams(){
    local data
    secondParmas=$1
    if [[ ${secondParmas}  == "" ]]; then
        print_log "${FUNCNAME}: 参数不能为空,退出告警自动恢复" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    data=$(echo "${secondParmas}" |tr "#" "\n" |sed "s/^/[/g" |sed "s/|/]=\"/g" |sed "s/$/\"/g"  |tr "\n" " ")
    echo "${data}"
}

#执行curl
runCurl(){
    local url=$1
    local args=$2
    local mtimeout=$3
    local tempfile=$4
    local lockFile=$5
    if [[ "${url}" == "" ]]; then
        print_log "请求URL不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${args}" == "" ]]; then
        print_log "请求参数不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${mtimeout}" == "" ]]; then
        print_log "请求超时不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${tempfile}" == "" ]]; then
        print_log "请求保存文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ "${lockFile}" == "" ]]; then
        print_log "请求锁文件不能为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    checkArgsCount=$(echo "${args}" |wc -l)
    if [[ "${checkArgsCount}" -ne 1 ]]; then
        print_log "请求参数不允许回车换行" "[ERROR] ${FUNCNAME} - " "31"
        print_log "参数如下: \n${args}"
        exit
    fi
    if [[ -f ${lockFile} ]]; then
        lockinfo=$(cat ${lockFile})
        print_log "请求锁已经存在,执行进程已经在运行,退出请求操作.\n${lockinfo}" "[ERROR] ${FUNCNAME} - " "31"
        exit
    else
        echo "请求远程执行命令" > ${lockFile}
        echo "开始时间: $(datef)" >> ${lockFile}
        echo "请求url: $url" >> ${lockFile}
        echo "请求参数:\n${formatArgs}" >> ${lockFile}
        echo "超时时间:${mtimeout}" >> ${lockFile}
        echo "保存文件:${tempfile}" >> ${lockFile}    
    fi
    formatArgs=$( echo "${args}"|tr "\-\-" "\n" |grep -v "^$" |sed "s/form/\-\-form/g")
    print_log "请求url: $url" "[INFO] ${FUNCNAME} -  "
    print_log "请求参数:\n${formatArgs}" "[INFO] ${FUNCNAME} -  "
    print_log "执行主机:${host}" "[INFO] ${FUNCNAME} -  "
    print_log "超时时间:${mtimeout}" "[INFO] ${FUNCNAME} -  "
    print_log "保存文件:${tempfile}" "[INFO] ${FUNCNAME} -  "
    
    if [[  -f  ${tempfile} ]]; then
        rm -f ${tempfile}
    fi
    # print_log "执行命令: curl --request POST --url \"${url}\" --header \"cache-control: no-cache\" --header \"content-type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW\" ${args} -w  -I -m ${mtimeout} -o ${tempfile} -s -w %{http_code}"
    start=$(date "+%s")
    echo -e  "curl --request POST --url \"${url}\" --header \"cache-control: no-cache\" --header \"content-type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW\" ${args} -w  -I -m ${mtimeout} -o ${tempfile} -s -w %{http_code}" > ${tempDir}/curl_${eventId}.sh
    if [[ ! -f  ${tempDir}/curl_${eventId}.sh ]]; then
        print_log "生成临时curl脚本失败" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    # http_code=$(eval curl --request POST --url "${url}" --header "cache-control: no-cache" --header "content-type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW" ${args} -w  -I -m ${mtimeout} -o ${tempfile} -s -w %{http_code})
    /bin/bash  ${tempDir}/curl_${eventId}.sh > ${tempDir}/code_${eventId}.txt
    http_code=$(cat ${tempDir}/code_${eventId}.txt |sed "s/ //g")
    httpRret=$?
    if [[ -f ${lockFile} ]]; then
        rm -f ${lockFile}
    fi
    if [[ ${httpRret} -ne 0 ]]; then
        if [[ ! -f  ${tempfile} ]]; then
            print_log "执行curl命令失败,未形成curl文件,请检查curl参数" "[ERROR] ${FUNCNAME} - " "31"
            exit
        fi   
        
    fi
    end=$(date "+%s")
    take=$(expr $end - $start)
    fileCount=$(cat ${tempfile} |wc -l)
    stdoutNumber=$(cat ${tempfile} |grep -n  "\"stdout\"\:" |awk -F':' '{print $1}')
    stderrNumber=$(cat ${tempfile}  |grep -n  "\"stderr\"\:" |awk -F':' '{print $1}')
    takeNumber=$(cat ${tempfile}  |grep -n  "\"takes\"\:" |awk -F':' '{print $1}')
    msg=$(cat ${tempfile}  |grep "\"msg\":" |grep -v "^$" |tail -n 1 |awk -F':' '{print $2}' |sed "s/\"//g" )
    # if [[ ! -z `echo "${msg}" |grep "\\u"` ]]; then
    #     msg=$(echo "${msg}"|sed "s#\u#\\\u#g")
    # fi
    if [[ ${stdoutNumber} = "" ]]; then
        print_log "返回标准输出字段不存在" "[WARN] ${FUNCNAME} - "
    else
        lastNumber=$(expr ${takeNumber} - 1)
        stdout=$(sed -n "${stdoutNumber},${lastNumber}p" ${tempfile})
    fi
    if [[ ${stderrNumber} = "" ]]; then
        print_log "返回错误输出字段不存在" "[WARN] ${FUNCNAME} - "
    else
        lastNumber=$(expr ${stdoutNumber} - 1)
        stderr=$(sed -n "${stderrNumber},${lastNumber}p" ${tempfile})
    fi
    print_log "请求返回结果,返回码:${http_code} 返回消息提示:`echo -e "${msg}"` 花费时间:${take}秒" "[INFO] ${FUNCNAME} -  "
    print_log "标准输出: \n${stdout}" "[INFO] ${FUNCNAME} -  "
    print_log "错误输出: ${stderr} " "[INFO] ${FUNCNAME} -  "
}

#执行远程命令
runCmd(){
    local environment=$1
    local host=$2
    local cmd=$3
    local returncode=$4
    local returnreqiure=$5
    local returntimeout=$6
    local url
    local conf
    local argsArray
    local m=0
    local hostIndex
    local cmdIndex
    local mtimeout
    local tempfile
    local lockFile
    environment=$(echo "${environment}" |sed "s/ //g")
    host=$(echo "${host}" |sed "s/ //g")
    if [[ ${environment}  == "" ]]; then
        print_log "执行环境为空,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ ${host}  == "" ]]; then
        print_log "执行主机,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ ${cmd}  == "" ]]; then
        print_log "执行命令,退出" "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    case ${environment}  in
        dev)
            local url=${devConf[api]}
            local devCount=${#devConf[*]}
            for conf in $(echo ${!devConf[*]})
            do
                argsArray[${m}]="--form '${conf}=${devConf[${conf}]}' "
                m=$(expr $m + 1)
            done
            hostIndex=$(expr ${devCount} + 1 )
            cmdIndex=$(expr ${hostIndex} + 1 )
            argsArray[${hostIndex}]="--form 'hosts=${host}' "
            argsArray[${cmdIndex}]="--form 'cmd=${cmd}' "
            local args=$(echo "${argsArray[*]}")
            if [[ "${returntimeout}" != "" ]]; then
                mtimeout=${returntimeout}
            else
                mtimeout=${devConf[returntimeout]}
            fi
            local sshUsernameRedefined
            if [[ "${sshUsername}" != "" ]]; then
                sshUsernameRedefined=${sshUsernameRedefined}
            else
                sshUsernameRedefined=${devConf[sshUsername]} 
            fi
            local sshPasswordRedefined
            if [[ "${sshPassword}" != "" ]]; then
                sshPasswordRedefined=${sshPassword}
            else
                sshPasswordRedefined=${devConf[sshPassword]} 
            fi
            if [[ "${eventId}" == ""  ]]; then
                print_log "获取事件ID失败" "[ERROR] ${FUNCNAME} - " "31"
            fi
            tempfile="${tempDir}/curlsave_${eventId}.txt"
            lockFile="${tempDir}/lock_${eventId}.txt"
            local commonRunlevel=${devConf[runlevel]}
            case ${runlevel} in
                0 )
                    runType="自定义API接口"
                    runCurl "${url}" "${args}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                1 )
                    runType="salt-API接口"
                    getsaltToken "${devConf[saltUrl]}" "${devConf[saltUsername]}" "${devConf[saltPassword]}"
                    runsaltTask "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                2 )
                    runType="免秘钥ssh执行"
                    keyLessRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                3 )
                    runType="[expect]ssh执行"
                    sshExpectRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                    ;;
                4 )
                    runType="ansible远程执行"
                    ansibleRun "${host}" "${cmd}" "${mtimeout}"  "${tempfile}" "${lockFile}"
                    ;;
                5)
                    runType="sshpass远程执行"
                    sshPassRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                    ;;
                "" )
                    case ${commonRunlevel} in
                        0 )
                            runType="自定义API接口"
                            runCurl "${url}" "${args}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        1 )
                            runType="salt-API接口"
                            getsaltToken "${devConf[saltUrl]}" "${devConf[saltUsername]}" "${devConf[saltPassword]}"
                            runsaltTask "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        2 )
                            runType="免秘钥ssh执行"
                            keyLessRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        3 )
                            runType="[expect]ssh执行"
                            sshExpectRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                            ;;
                        4 )
                            runType="ansible远程执行"
                            ansibleRun "${host}" "${cmd}" "${mtimeout}"  "${tempfile}" "${lockFile}"
                            ;;
                        5)
                            runType="sshpass远程执行"
                            sshPassRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                            ;;
                        "" )
                            print_log "运行方式全局和规则配置不能同时为空,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                            ;;
                        * )
                            print_log "运行方式配置错误,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                            ;;
                    esac

                    ;;
                * )
                    print_log "运行方式配置错误,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                    ;;
            esac
            ;;
        test)
            local url=${testConf[api]}
            local devCount=${#testConf[*]}
            for conf in $(echo ${!testConf[*]})
            do
                argsArray[${m}]="--form '${conf}=${testConf[${conf}]}' "
                m=$(expr $m + 1)
            done
            hostIndex=$(expr ${devCount} + 1 )
            cmdIndex=$(expr ${hostIndex} + 1 )
            argsArray[${hostIndex}]="--form 'hosts=${host}' "
            argsArray[${cmdIndex}]="--form 'cmd=${cmd}' "
            local args=$(echo "${argsArray[*]}")
            if [[ "${returntimeout}" != "" ]]; then
                mtimeout=${returntimeout}
            else
                mtimeout=${testConf[returntimeout]}
            fi
            local sshUsernameRedefined
            if [[ "${sshUsername}" != "" ]]; then
                sshUsernameRedefined=${sshUsernameRedefined}
            else
                sshUsernameRedefined=${testConf[sshUsername]} 
            fi
            local sshPasswordRedefined
            if [[ "${sshPassword}" != "" ]]; then
                sshPasswordRedefined=${sshPassword}
            else
                sshPasswordRedefined=${testConf[sshPassword]} 
            fi
            if [[ "${eventId}" == ""  ]]; then
                print_log "获取事件ID失败" "[ERROR] ${FUNCNAME} - " "31"
            fi
            tempfile="${tempDir}/curlsave_${eventId}.txt"
            lockFile="${tempDir}/lock_${eventId}.txt"
            local commonRunlevel=${testConf[runlevel]}
            case ${runlevel} in
                0 )
                    runType="自定义API接口"
                    runCurl "${url}" "${args}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                1 )
                    runType="salt-API接口"
                    getsaltToken "${testConf[saltUrl]}" "${testConf[saltUsername]}" "${testConf[saltPassword]}"
                    runsaltTask "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                2 )
                    runType="免秘钥ssh执行"
                    keyLessRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                3 )
                    runType="[expect]ssh执行"
                    sshExpectRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                    ;;
                4 )
                    runType="ansible远程执行"
                    ansibleRun "${host}" "${cmd}" "${mtimeout}"  "${tempfile}" "${lockFile}"
                    ;;
                5)
                    runType="sshpass远程执行"
                    sshPassRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                    ;;
                "" )
                    case ${commonRunlevel} in
                        0 )
                            runType="自定义API接口"
                            runCurl "${url}" "${args}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        1 )
                            runType="salt-API接口"
                            getsaltToken "${testConf[saltUrl]}" "${testConf[saltUsername]}" "${testConf[saltPassword]}"
                            runsaltTask "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        2 )
                            runType="免秘钥ssh执行"
                            keyLessRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        3 )
                            runType="[expect]ssh执行"
                            sshExpectRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                            ;;
                        4 )
                            runType="ansible远程执行"
                            ansibleRun "${host}" "${cmd}" "${mtimeout}"  "${tempfile}" "${lockFile}"
                            ;;
                        5)
                            runType="sshpass远程执行"
                            sshPassRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                            ;;
                        "" )
                            print_log "运行方式全局和规则配置不能同时为空,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                            ;;
                        * )
                            print_log "运行方式配置错误,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                            ;;
                    esac

                    ;;
                * )
                    print_log "运行方式配置错误,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                    ;;
            esac
            ;;
        52zzb)
            local url=${zzbConf[api]}
            local devCount=${#zzbConf[*]}
            for conf in $(echo ${!zzbConf[*]})
            do
                argsArray[${m}]="--form '${conf}=${zzbConf[${conf}]}' "
                m=$(expr $m + 1)
            done
            hostIndex=$(expr ${devCount} + 1 )
            cmdIndex=$(expr ${hostIndex} + 1 )
            argsArray[${hostIndex}]="--form 'hosts=${host}' "
            argsArray[${cmdIndex}]="--form 'cmd=${cmd}' "
            local args=$(echo "${argsArray[*]}")
            if [[ "${returntimeout}" != "" ]]; then
                mtimeout=${returntimeout}
            else
                mtimeout=${zzbConf[returntimeout]}
            fi
            local sshUsernameRedefined
            if [[ "${sshUsername}" != "" ]]; then
                sshUsernameRedefined=${sshUsernameRedefined}
            else
                sshUsernameRedefined=${zzbConf[sshUsername]} 
            fi
            local sshPasswordRedefined
            if [[ "${sshPassword}" != "" ]]; then
                sshPasswordRedefined=${sshPassword}
            else
                sshPasswordRedefined=${zzbConf[sshPassword]} 
            fi
            if [[ "${eventId}" == ""  ]]; then
                print_log "获取事件ID失败" "[ERROR] ${FUNCNAME} - " "31"
            fi
            tempfile="${tempDir}/curlsave_${eventId}.txt"
            lockFile="${tempDir}/lock_${eventId}.txt"
            local commonRunlevel=${zzbConf[runlevel]}
            case ${runlevel} in
                0 )
                    runType="自定义API接口"
                    runCurl "${url}" "${args}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                1 )
                    runType="salt-API接口"
                    getsaltToken "${zzbConf[saltUrl]}" "${zzbConf[saltUsername]}" "${zzbConf[saltPassword]}"
                    runsaltTask "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                2 )
                    runType="免秘钥ssh执行"
                    keyLessRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                3 )
                    runType="[expect]ssh执行"
                    sshExpectRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                    ;;
                4 )
                    runType="ansible远程执行"
                    ansibleRun "${host}" "${cmd}" "${mtimeout}"  "${tempfile}" "${lockFile}"
                    ;;
                5)
                    runType="sshpass远程执行"
                    sshPassRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                    ;;
                "" )
                    case ${commonRunlevel} in
                        0 )
                            runType="自定义API接口"
                            runCurl "${url}" "${args}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        1 )
                            runType="salt-API接口"
                            getsaltToken "${zzbConf[saltUrl]}" "${zzbConf[saltUsername]}" "${zzbConf[saltPassword]}"
                            runsaltTask "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        2 )
                            runType="免秘钥ssh执行"
                            keyLessRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        3 )
                            runType="[expect]ssh执行"
                            sshExpectRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                            ;;
                        4 )
                            runType="ansible远程执行"
                            ansibleRun "${host}" "${cmd}" "${mtimeout}"  "${tempfile}" "${lockFile}"
                            ;;
                        5)
                            runType="sshpass远程执行"
                            sshPassRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                            ;;
                        "" )
                            print_log "运行方式全局和规则配置不能同时为空,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                            ;;
                        * )
                            print_log "运行方式配置错误,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                            ;;
                    esac

                    ;;
                * )
                    print_log "运行方式配置错误,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                    ;;
            esac
            ;;
        com)
            local url=${comConf[api]}
            local devCount=${#comConf[*]}
            for conf in $(echo ${!comConf[*]})
            do
                argsArray[${m}]="--form '${conf}=${comConf[${conf}]}' "
                m=$(expr $m + 1)
            done
            hostIndex=$(expr ${devCount} + 1 )
            cmdIndex=$(expr ${hostIndex} + 1 )
            argsArray[${hostIndex}]="--form 'hosts=${host}' "
            argsArray[${cmdIndex}]="--form 'cmd=${cmd}' "
            local args=$(echo "${argsArray[*]}")
            if [[ "${returntimeout}" != "" ]]; then
                mtimeout=${returntimeout}
            else
                mtimeout=${comConf[returntimeout]}
            fi
            local sshUsernameRedefined
            if [[ "${sshUsername}" != "" ]]; then
                sshUsernameRedefined=${sshUsernameRedefined}
            else
                sshUsernameRedefined=${comConf[sshUsername]} 
            fi
            local sshPasswordRedefined
            if [[ "${sshPassword}" != "" ]]; then
                sshPasswordRedefined=${sshPassword}
            else
                sshPasswordRedefined=${comConf[sshPassword]} 
            fi
            if [[ "${eventId}" == ""  ]]; then
                print_log "获取事件ID失败" "[ERROR] ${FUNCNAME} - " "31"
            fi
            tempfile="${tempDir}/curlsave_${eventId}.txt"
            lockFile="${tempDir}/lock_${eventId}.txt"
            local commonRunlevel=${comConf[runlevel]}
            case ${runlevel} in
                0 )
                    runType="自定义API接口"
                    runCurl "${url}" "${args}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                1 )
                    runType="salt-API接口"
                    getsaltToken "${comConf[saltUrl]}" "${comConf[saltUsername]}" "${comConf[saltPassword]}"
                    runsaltTask "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                2 )
                    runType="免秘钥ssh执行"
                    keyLessRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                    ;;
                3 )
                    runType="[expect]ssh执行"
                    sshExpectRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                    ;;
                4 )
                    runType="ansible远程执行"
                    ansibleRun "${host}" "${cmd}" "${mtimeout}"  "${tempfile}" "${lockFile}"
                    ;;
                5)
                    runType="sshpass远程执行"
                    sshPassRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                    ;;
                "" )
                    case ${commonRunlevel} in
                        0 )
                            runType="自定义API接口"
                            runCurl "${url}" "${args}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        1 )
                            runType="salt-API接口"
                            getsaltToken "${comConf[saltUrl]}" "${comConf[saltUsername]}" "${comConf[saltPassword]}"
                            runsaltTask "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        2 )
                            runType="免秘钥ssh执行"
                            keyLessRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}"
                            ;;
                        3 )
                            runType="[expect]ssh执行"
                            sshExpectRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                            ;;
                        4 )
                            runType="ansible远程执行"
                            ansibleRun "${host}" "${cmd}" "${mtimeout}"  "${tempfile}" "${lockFile}"
                            ;;
                        5)
                            runType="sshpass远程执行"
                            sshPassRun  "${sshUsernameRedefined}" "${host}" "${cmd}" "${mtimeout}" "${tempfile}" "${lockFile}" "${sshPasswordRedefined}"
                            ;;
                        "" )
                            print_log "运行方式全局和规则配置不能同时为空,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                            ;;
                        * )
                            print_log "运行方式配置错误,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                            ;;
                    esac

                    ;;
                * )
                    print_log "运行方式配置错误,runlevel:${runlevel}" "[ERROR] ${FUNCNAME} - " "31";exit
                    ;;
            esac
            ;;
        *)
            print_log "执行环境变量不支持,目前仅支持dev/test/52zzb/com" "[ERROR] ${FUNCNAME} - " "31"
            exit
            ;;
    esac
}

#匹配规则3
match(){
    local condition=$1
    local conditionRes=$2
    local ReturnVal=$3
    if [[ ${condition}  == "" ]]; then
        return 199
    fi
    if [[ ${conditionRes}  == "" ]]; then
        return 199
    fi
    if [[ ${ReturnVal}  == "" ]]; then
        return 199
    fi 
    condition=$(echo "$condition" |sed "s/ //g") 
    conditionRes=$(echo "$conditionRes" |sed "s/^ //g" |sed "s/ $//g") 
    ReturnVal=$(echo "$ReturnVal" |sed "s/^ //g" |sed "s/ $//g") 
    case $condition in
         "gt" )
            if [[ $(echo "${ReturnVal} > ${conditionRes}" | bc) -eq 1 ]];then 
                return 1
            else 
                return 99
            fi             
             ;;
         "ge" )
            if [[ $(echo "${ReturnVal} >= ${conditionRes}" | bc) -eq 1 ]];then 
                return 1
            else 
                return 99
            fi 
             ;;
         "eq" )
            if [[ $(echo "${ReturnVal} = ${conditionRes}" | bc) -eq 1 ]];then 
                return 1
            else 
                return 99
            fi 
             ;;
         "lt" )
            if [[ $(echo "${ReturnVal} < ${conditionRes}" | bc) -eq 1 ]];then 
                return 1
            else 
                return 99
            fi 
            ;;
         "le" )
            if [[ $(echo "${ReturnVal} <= ${conditionRes}" | bc) -eq 1 ]];then 
                return 1
            else 
                return 99
            fi           
             ;;
         "=" )
            if [[ "${ReturnVal}" = "${conditionRes}" ]]; then
                return 1
            else
                return 99
            fi            
             ;;
         "!=" )
            if [[ "${ReturnVal}" != "${conditionRes}" ]]; then
                return 1
            else
                return 99
            fi            
             ;;
         "like" )
            formatConditionRes=$(echo "${conditionRes}" |sed "s/^%//" |sed "s/%$//")
             if [[ ! -z `echo "${conditionRes}" |grep "^%"` && ! -z `echo "${conditionRes}" |grep "%$"` ]]; then 
                 if [[ -z $(echo "${ReturnVal}" |grep "${formatConditionRes}") ]];then
                    return 99
                 else
                    return 1
                 fi
             elif [[  ! -z `echo "${conditionRes}" |grep "^%"` &&  -z `echo "${conditionRes}" |grep "%$"` ]]; then
                 if [[ -z $(echo "${ReturnVal}" |grep "${formatConditionRes}$") ]];then
                    return 99
                 else
                    return 1
                 fi
             elif [[  -z `echo "${conditionRes}" |grep "^%"` && ! -z `echo "${conditionRes}" |grep "%$"` ]]; then
                 if [[ -z $(echo "${ReturnVal}" |grep "^${formatConditionRes}") ]];then
                    return 99
                 else
                    return 1
                 fi
            else
                 return 99
             fi
             
             ;;  
        *)
            return 99
        ;;                                     
    esac 
    return 20    
}

#匹配规则2
dealMatch(){
    if [[ ${#dict[*]} -eq 0  ]]; then
        print_log "匹配返回规则时获取字典参数为空." "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    if [[ ${#ruleDict[*]} -eq 0  ]]; then
        print_log "匹配配置规则时获取字典参数为空." "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi 
    successCount=0
    failCount=0
    for key in $(echo ${!ruleDict[*]})
    do
            key=$(echo "${key}" |sed "s/ //g")
            if [[ ! -z `echo " ${skipRuleParams[*]} "|grep " ${key} "` ]]; then
                continue
            fi
            keyValue=$(echo "${ruleDict[$key]}" |sed "s/^ //g" |sed "s/ $//g")
            condition=$(echo "${keyValue}" |awk -F',' '{print $1}' |sed "s/ //g" |sed "s/^{//")
            conditionRes=$(echo "${keyValue}" |sed "s/^{${condition},//"|sed "s/ $//"|sed "s/}$//")
            ReturnKeys=${!dict[*]}
            ReturnVal=${dict[$key]}
            #1.判断返回值的Key是否存在
            if [[ -z `echo  " ${ReturnKeys} " | grep " ${key} "` ]]; then
                print_log "匹配规则: 返回字典中不存在${key}的键,退出该条匹配" "[ERROR] ${FUNCNAME} - " "31"
                continue
            fi
            # print_log "匹配规则: 返回字典${key}都存在,serial=${ruleDict[serial]}" "[INFO] ${FUNCNAME} -  "
            #开始规则匹配
            if [[ "${key}" == "itemvalue" ]]; then
                ReturnVal=$(echo "${ReturnVal}" |sed "s/%//")
            fi
            if [[ "${key}" == "ipaddress" ]]; then
                host=$(echo "${ReturnVal}" |sed "s/ //g")
            fi
            print_log ""
            print_log "匹配键:${key}  匹配值:${conditionRes}  匹配条件:${condition}  待匹配目标:${ReturnVal}" "[INFO] ${FUNCNAME} -  "
            matchRes=$(match "${condition}" "${conditionRes}" "${ReturnVal}")
            res=$?
            if [[ ${res} == "1" ]]; then
                print_log "匹配规则成功" "[INFO] ${FUNCNAME} -  "
                successCount=$(expr ${successCount} + 1)
            elif [[ ${res} == "99" ]]; then
                failCount=$(expr ${failCount} + 1)
                print_log "匹配规则失败:${res}" "[ERROR] ${FUNCNAME} - " "31"
            elif [[ ${res} == "199" ]]; then
                failCount=$(expr ${failCount} + 1)
                print_log "匹配规则失败,匹配的条件异常,返回code:${res}" "[ERROR] ${FUNCNAME} - " "31"
            else
                failCount=$(expr ${failCount} + 1)
                print_log "匹配规则失败,获取返回值异常,返回code:${res}" "[ERROR] ${FUNCNAME} - " "31"
            fi
            print_log ""

    done       
}

#匹配规则1
matchRule(){
    if [[ ${#dict[*]} -eq 0  ]]; then
        print_log "匹配返回规则时获取字典参数为空." "[ERROR] ${FUNCNAME} - " "31"
        exit
    fi
    print_log ""
    print_log "开始解析规则配置表:${ruleConf}" "[INFO] ${FUNCNAME} -  "
    ruleCount=$(cat ${ruleConf} |grep -v "^#" |grep -v "^$" |wc -l)
    print_log "合计有${ruleCount}条规则,开始将规则配置转换成字典配置." "[INFO] ${FUNCNAME} -  "
    count=1
    while read line
    do
        if [[ ! -z `echo  "${line}" |grep "^#"` ]]; then
            continue
        fi
        if [[ -z `echo  "${line}"` ]]; then
            continue
        fi        
        print_log ""
        print_log ""
        print_log "开始,解析配置表第${count}条规则" "[INFO] ${FUNCNAME} -  "
        ruleContent=$(echo "$line" |tr "||" "\n"|grep -v "^$" |sed "s/^ //g"|sed "s/^/[/g"|sed "s/:/]=\"/g" |sed "s/$/\"/g" |tr "\n" " ")
        ruleCountContent=$(echo "$line" |tr "||" "\n"|grep -v "^$" |grep -v "^$" |sed "s/^ //g"|sed "s/ :/:/g")
        for (( i = 0; i < ${skipRuleCount}; i++ )); do
            ruleCountContent=$(echo "${ruleCountContent}" |grep -v "^${skipRuleParams[$i]}:")
        done
        ruleCount=$(echo "${ruleCountContent}" |wc -l)   
        print_log "解析后规则字典内容: ${ruleContent}  " "[INFO] ${FUNCNAME} -  "
        declare -A ruleDict
        eval ruleDict=(${ruleContent}) &> /dev/null
        if [[ $? -ne 0 ]]; then
            print_log "构建规则字典失败,请检查规则配置是否正确,跳过该条规则匹配" "[ERROR] ${FUNCNAME} -  " "31"
            continue
        fi
        print_log "解析配置表第${count}条规则,正常" "[INFO] ${FUNCNAME} -  "
        serial=${ruleDict["serial"]}
        envi=${ruleDict["env"]}
        isactive=${ruleDict["isactive"]}
        triggervalue=${ruleDict["triggervalue"]}
        ipaddress=${ruleDict["ipaddress"]}
        triggername=${ruleDict["triggername"]}
        triggerkey=${ruleDict["triggerkey"]}
        itemvalue=${ruleDict["itemvalue"]}
        cmd=${ruleDict["cmd"]}
        returncode=$(echo "${ruleDict["returncode"]}"|sed "s/ //g")
        returnreqiure=${ruleDict["returnreqiure"]}
        returntimeout=${ruleDict["returntimeout"]}
        ischeck=${ruleDict["ischeck"]}
        runlevel=${ruleDict["runlevel"]}
        sshUsername=${ruleDict["sshUsername"]}
        sshPassword=${ruleDict["sshPassword"]}
        if [[ ${isactive} -eq 0 ]]; then
            print_log "该条规则serial:${serial}未启用,跳过该条规则匹配" "[INFO] ${FUNCNAME} -  "
            continue
        fi
        dealMatch
        if [[ ${successCount} -eq  ${ruleCount} &&  ${failCount} -eq 0 ]] ;then
            print_log "第${count}条规则,匹配规则结果: 成功 规则配置数量:${ruleCount} 成功数量:${successCount} 失败数量:${failCount}" "[INFO] ${FUNCNAME} -  "  "32"
            runCmd "${envi}" "${host}" "${cmd}" "${returncode}" "${returnreqiure}" "${returntimeout}"
            checkResult
        else
            print_log "第${count}条规则,匹配规则结果: 失败 规则配置数量:${ruleCount} 成功数量:${successCount} 失败数量:${failCount}" "[ERROR] ${FUNCNAME} - " "31"
        fi
        count=`expr ${count} + 1`
    done < ${ruleConf}
}

#检查返回结果
checkResult(){
    local matchRes
    local res
    local condition
    local conditionRes
    local ReturnVal
    condition=$(echo "${ruleDict[returnreqiure]}" |awk -F',' '{print $1}' |sed "s/ //g" |sed "s/^{//")
    conditionRes=$(echo "${ruleDict[returnreqiure]}"|sed "s/^{${condition},//"|sed "s/ $//"|sed "s/}$//")
    ReturnVal=${stdout}  
    forMatReturnVal=$(echo "${stdout}" |sed "s/^ //g"|sed "s/ $//g" |tr "\n" "\\n" |sed "s/\"/\'/g" |sed "s#“##g"|sed "s#”##g")
    if [[ ${ischeck} -ne 1 ]]; then
        print_log "ischeck !=1 不校验返回结果" "[WARN] ${FUNCNAME} - "
        return 88
    fi
    print_log "开始校验Curl返回结果" "[INFO] ${FUNCNAME} -  "
    if [[ "${http_code}" == "${returncode}" ]]; then
        print_log "返回码校验成功code:${returncode}" "[INFO] ${FUNCNAME} -  " 
    else
        print_log "返回码校验失败,匹配code:${returncode} 返回code:${http_code}" "[ERROR] ${FUNCNAME} - " "31"
    fi
    print_log "校验匹配 键:returnreqiure 条件:${condition} 匹配条件:${conditionRes} 匹配返回值:${forMatReturnVal}" "[INFO ]  ${FUNCNAME} - "
    matchRes=$(match "${condition}" "${conditionRes}" "${ReturnVal}")
    res=$?
    local temVal=0
    if [[ ${res} == "1" ]]; then
        temVal=1
        print_log "校验匹配规则成功" "[INFO] ${FUNCNAME} -  "
        sendWeixin "故障自愈成功-${host}-${dict[triggername]}\n自愈执行命令:${cmd}\n返回状态码:${http_code}\n执行主机:${host}\n执行方式:${runType}\n执行时间:${take}秒\n返回内容:${forMatReturnVal}"
        sendMail "故障自愈成功-${host}-${dict[triggername]}" "自愈执行命令:${cmd}\n返回状态码:${http_code}\n执行主机:${host}\n执行方式:${runType}\n执行时间:${take}秒\n返回内容:${forMatReturnVal}" &

    elif [[ ${res} == "99" ]]; then  
        print_log "校验匹配规则失败:${res}" "[ERROR] ${FUNCNAME} - " "31"
    elif [[ ${res} == "199" ]]; then     
        print_log "校验匹配规则失败,匹配的条件异常,返回code:${res}" "[ERROR] ${FUNCNAME} - " "31"
    else
        print_log "校验匹配规则失败,获取返回值异常,返回code:${res}" "[ERROR] ${FUNCNAME} - " "31"
    fi
    if [[ ${temVal}  -eq 0 ]]; then
        sendWeixin "故障自愈失败-${host}-${dict[triggername]}\n自愈执行命令:${cmd}\n返回状态码:${http_code}\n执行主机:${host}\n执行方式:${runType}\n执行时间:${take}秒\n返回内容:${forMatReturnVal}"
        sendMail "故障自愈失败-${host}-${dict[triggername]}" "自愈执行命令:${cmd}\n返回状态码:${http_code}\n执行主机:${host}\n执行方式:${runType}\n执行时间:${take}秒\n返回内容:${stdout}" &
    fi
}

#执行主函数
main(){
    first=$1
    second=$2
    if [[ $1 == "" || $2 == "" ]]; then
        print_log "第1个参数或者第2个参数不能为空" "[ERROR] ${FUNCNAME} - " "31";exit
    fi
    if [[ $# != 2 ]]; then
        print_log "至少需要2个参数,退出告警自动恢复" "[ERROR] ${FUNCNAME} - " "31";exit
        exit
    fi
    checkSyshell
    source ${commonConf}
    skipRuleCount=${#skipRuleParams[*]}
    formatSecond=$(echo "${second}" |tr "#" "\n" |sed "s/^/\"/g" |sed "s/|/\":\"/g" |sed "s/$/\",/g"  |sed "s/^/        /g")
    print_log "获取参数个数: $#" "[INFO] ${FUNCNAME} -  "
    print_log "第1个参数: $first" "[INFO] ${FUNCNAME} -  "
    print_log "第2个参数: \n{\n${formatSecond}\n}" "[INFO] ${FUNCNAME} -  "

    declare -A dict
    eval data=($(dealFirstParams "$first"))
    firstCheck "${data[*]}"
    eval dict=($(dealSecondParams "$second"))
    print_log "返回字典格式正确1: ${!dict[*]}" "[INFO] ${FUNCNAME} -  "
    print_log "返回字典格式正确2: ${dict[*]}" "[INFO] ${FUNCNAME} -  "
    matchRule
}
main "$1" "$2"



