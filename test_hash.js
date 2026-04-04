console.log(require('crypto').pbkdf2Sync('favorites_user_1', 'd8b0ca99b31bfb3856b642f4eb357405', 100000, 32, 'sha256').toString('hex'))
