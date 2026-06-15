import { NextResponse } from "next/server";

import { bridgeConfigMessage, ensureDevConfiguration } from "../_bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  try {
    await ensureDevConfiguration();
    return NextResponse.json({
      configured: true,
      message: "Bridge configured",
      instructions: [],
    });
  } catch {
    return NextResponse.json({
      configured: false,
      message: bridgeConfigMessage(),
      instructions: [
        "Set TBE_REPO_ROOT",
        "Set TBE_APPLY_COMMAND",
        "Set TBE_WORKING_PROJECT",
        "Set TBE_VIEWER_SAMPLE_DIR",
      ],
    });
  }
}
