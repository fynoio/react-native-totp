package io.fyno.reactnativetotp.models

import android.view.Window
import com.google.gson.annotations.SerializedName

data class SuccessResponse(
    @SerializedName("enrolment_id") val enrolmentId: String,
    val config: TotpConfig
)

data class TotpConfig(
    val tenant_id: String,
    val tenant_name: String,
    val digits: Int,
    val period: Int,
    val algorithm: String
)
