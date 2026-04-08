import { useState } from 'react';
import { Modal, Form, Input, Typography, Space } from 'antd';
import { ExclamationCircleOutlined } from '@ant-design/icons';

const { Text } = Typography;
const { TextArea } = Input;

interface ConfirmActionProps {
  open: boolean;
  title: string;
  description?: string;
  requireReason?: boolean;
  reasonLabel?: string;
  reasonPlaceholder?: string;
  onConfirm: (reason?: string) => void | Promise<void>;
  onCancel: () => void;
  loading?: boolean;
  danger?: boolean;
  confirmText?: string;
}

export function ConfirmAction({
  open,
  title,
  description,
  requireReason = false,
  reasonLabel = '처리 사유',
  reasonPlaceholder = '사유를 입력해주세요.',
  onConfirm,
  onCancel,
  loading = false,
  danger = true,
  confirmText = '확인',
}: ConfirmActionProps) {
  const [form] = Form.useForm();
  const [confirming, setConfirming] = useState(false);

  const handleConfirm = async () => {
    try {
      if (requireReason) {
        await form.validateFields();
      }
      const values = form.getFieldsValue();
      setConfirming(true);
      await onConfirm(values.reason);
      form.resetFields();
    } catch {
      // validation error
    } finally {
      setConfirming(false);
    }
  };

  const handleCancel = () => {
    form.resetFields();
    onCancel();
  };

  return (
    <Modal
      open={open}
      title={
        <Space>
          <ExclamationCircleOutlined style={{ color: danger ? '#ff4d4f' : '#fa8c16' }} />
          {title}
        </Space>
      }
      onOk={handleConfirm}
      onCancel={handleCancel}
      okText={confirmText}
      cancelText="취소"
      okButtonProps={{
        danger,
        loading: loading || confirming,
      }}
    >
      {description && (
        <Text type="secondary" style={{ display: 'block', marginBottom: 12 }}>
          {description}
        </Text>
      )}

      {requireReason && (
        <Form form={form} layout="vertical">
          <Form.Item
            name="reason"
            label={reasonLabel}
            rules={[{ required: true, message: '사유를 입력해주세요.' }]}
          >
            <TextArea rows={3} placeholder={reasonPlaceholder} showCount maxLength={500} />
          </Form.Item>
        </Form>
      )}
    </Modal>
  );
}
