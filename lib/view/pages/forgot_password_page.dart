/// 找回密码页面，提供账号密码重置入口。

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:photo_album/service/cognito_auth_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _auth = const CognitoAuthService();
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _submitting = false;
  bool _awaitingCode = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _usernameController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _success = null;
    });

    try {
      final result = await _auth.resetPassword(
        username: _usernameController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      if (result.isPasswordReset) {
        setState(() {
          _success = '密码已重置，请返回登录';
          _awaitingCode = false;
        });
      } else {
        setState(() {
          _awaitingCode = true;
          _success = '验证码已发送，请输入验证码并设置新密码';
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _error = '发送验证码失败，请稍后重试';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _confirmReset() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = '请输入验证码';
      });
      return;
    }
    if (_newPasswordController.text.length < 8) {
      setState(() {
        _error = '新密码至少 8 位';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _success = null;
    });

    try {
      await _auth.confirmResetPassword(
        username: _usernameController.text.trim(),
        confirmationCode: code,
        newPassword: _newPasswordController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _success = '密码重置成功，请返回登录';
      });
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _error = '密码重置失败，请稍后重试';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('找回密码')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: '用户名'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入用户名';
                    }
                    return null;
                  },
                ),
                if (_awaitingCode) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(labelText: '验证码'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newPasswordController,
                    decoration: const InputDecoration(labelText: '新密码'),
                    obscureText: true,
                  ),
                ],
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_success != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _success!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting
                        ? null
                        : (_awaitingCode ? _confirmReset : _sendCode),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_awaitingCode ? '确认重置密码' : '发送重置验证码'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}