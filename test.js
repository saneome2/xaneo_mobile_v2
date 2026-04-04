console.log(require('crypto').pbkdf2Sync('favorites_user_1', 'salt', 100000, 32, 'sha256').toString('hex'))
