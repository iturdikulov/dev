#!/bin/bash

HOST="192.168.1.114"
USER="root"

echo "Отправка команды на выключение принтера $HOST..."
ssh $USER@$HOST "shutdown -h now"
