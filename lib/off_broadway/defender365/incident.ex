defmodule OffBroadway.Defender365.Incident do
  @moduledoc """
  This module contains `ExConstructor` modules for the various entities contained
  within an incident.
  """
  defmodule Metadata do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [
      :assigned_to,
      :classification,
      :comments,
      :created_time,
      :detection_source,
      :determination,
      :incident_id,
      :incident_name,
      :last_update_time,
      :redirect_incident_id,
      :severity,
      :status,
      :tags,
      :tenant_id
    ]

    use ExConstructor
  end

  defmodule Comment do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [:comment, :created_by, :created_time]
    use ExConstructor
  end

  defmodule Alert do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [
      :actor_name,
      :alert_id,
      :assigned_to,
      :category,
      :classification,
      :creation_time,
      :description,
      :determination,
      :devices,
      :entities,
      :first_activity,
      :incident_id,
      :investigation_state,
      :last_update_time,
      :mitre_techniques,
      :resolved_time,
      :service_source,
      :severity,
      :status,
      :threat_family_name,
      :title
    ]

    use ExConstructor
  end

  defmodule Device do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [
      :aa_device_id,
      :device_dns_name,
      :device_id,
      :first_seen,
      :health_status,
      :os_build,
      :os_platform,
      :rbac_group_name,
      :risk_score
    ]

    use ExConstructor
  end

  defmodule Entity do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [
      :aa_user_id,
      :account_name,
      :cluster_by,
      :delivery_action,
      :device_id,
      :domain_name,
      :entity_type,
      :file_name,
      :file_path,
      :ip_address,
      :mailbox_address,
      :mailbox_display_name,
      :parent_process_creation_time,
      :parent_process_id,
      :process_command_line,
      :process_creation_time,
      :process_id,
      :recipient,
      :registry_hive,
      :registry_key,
      :registry_value,
      :registry_value_type,
      :security_group_id,
      :security_group_name,
      :sender,
      :sha1,
      :sha256,
      :subject,
      :url,
      :user_principal_name,
      :user_sid
    ]

    use ExConstructor
  end
end
