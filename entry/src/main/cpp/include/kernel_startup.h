/*
 * SiYuan - From thought to insight, with agents
 * Copyright (c) 2020-present, b3log.org
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

#ifndef SIYUAN_KERNEL_STARTUP_H
#define SIYUAN_KERNEL_STARTUP_H

#include <cerrno>
#include <cstdint>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

// 检查固定端口是否可以绑定，探测结束后立即关闭套接字。
inline int GetKernelPortError(uint16_t port) {
    const int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        return errno;
    }

    // 与 Go 的 TCP 监听保持相同的地址复用设置，允许复用已关闭连接的端口。
    const int reuse = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) != 0) {
        const int error = errno;
        close(fd);
        return error;
    }

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(port);
    const int result = bind(fd, reinterpret_cast<const sockaddr *>(&address), sizeof(address));
    const int error = result == 0 ? 0 : errno;
    close(fd);
    return error;
}

#endif
