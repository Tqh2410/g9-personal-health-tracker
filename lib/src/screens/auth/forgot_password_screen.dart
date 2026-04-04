import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth_widgets.dart';
import '../../models/auth_exception.dart';
import '../../utils/user_friendly_error.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _handlePasswordReset() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(
        passwordResetProvider(_emailController.text.trim()).future,
      );

      setState(() {
        _emailSent = true;
      });
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = UserFriendlyError.message(
          e,
          fallback:
              'Không thể gửi email đặt lại mật khẩu lúc này. Vui lòng thử lại.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: scheme.onSurface),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_emailSent) ...[
                const AuthHeader(
                  title: 'Đặt lại mật khẩu',
                  subtitle:
                      'Chúng tôi sẽ gửi liên kết đặt lại mật khẩu cho bạn',
                ),
                const SizedBox(height: 40),
                Form(
                  key: _formKey,
                  child: CustomTextField(
                    label: 'Địa chỉ email',
                    hintText: 'Nhập email của bạn',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.email_outlined),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng nhập email';
                      }
                      if (!RegExp(
                        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                      ).hasMatch(value)) {
                        return 'Email không hợp lệ';
                      }
                      return null;
                    },
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      border: Border.all(color: scheme.error),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                CustomButton(
                  text: 'Gửi liên kết đặt lại',
                  onPressed: _handlePasswordReset,
                  isLoading: _isLoading,
                  width: double.infinity,
                ),
              ] else ...[
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.mark_email_read_outlined,
                        size: 80,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 24),
                      const AuthHeader(
                        title: 'Kiểm tra email của bạn',
                        subtitle: 'Chúng tôi đã gửi liên kết đặt lại mật khẩu',
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          border: Border.all(color: scheme.primary),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Liên kết đặt lại mật khẩu đã được gửi đến ${_emailController.text}. '
                          'Vui lòng kiểm tra email và làm theo hướng dẫn.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(height: 32),
                      CustomButton(
                        text: 'Quay lại đăng nhập',
                        onPressed: () => context.go('/login'),
                        width: double.infinity,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
