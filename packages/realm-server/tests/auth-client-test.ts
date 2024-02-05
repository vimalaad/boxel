import { module, test } from 'qunit';

import '@cardstack/runtime-common/helpers/code-equality-assertion';
import { RealmAuthClient } from '@cardstack/runtime-common/realm-auth-client';
import jwt from 'jsonwebtoken';
import { MatrixClient } from '@cardstack/runtime-common/matrix-client';

function createJWT(expiresIn: string | number) {
  return jwt.sign({}, 'secret', { expiresIn });
}

module('realm-auth-client', function (assert) {
  let client: RealmAuthClient;

  assert.beforeEach(function () {
    client = new RealmAuthClient(
      'user',
      'password',
      new URL('http://testmatrix.com/'),
      new URL('http://testrealm.com/'),
    ) as any;
    let mockMatrixClient = {
      async login() {
        return Promise.resolve();
      },
      async getRooms() {
        return Promise.resolve({ joined_rooms: [] });
      },
      async joinRoom() {
        return Promise.resolve();
      },
      async sendRoomEvent() {
        return Promise.resolve();
      },
    };

    // [] notation is a hack to make TS happy so we can set private properties with mocks
    client['matrixClient'] = mockMatrixClient as unknown as MatrixClient;
    client['initiateSessionRequest'] = async function (): Promise<Response> {
      return {
        status: 401,
        json() {
          return Promise.resolve({
            room: 'room',
            challenge: 'challenge',
          });
        },
      } as Response;
    };
    client['challengeRequest'] = async function (): Promise<Response> {
      return {
        headers: {
          get() {
            return createJWT('1h');
          },
        },
      } as unknown as Response;
    };
  });

  test('it authenticates and caches the jwt until it expires', async function (assert) {
    let jwtFromClient = await client.getJWT();

    assert.ok(
      jwtFromClient.split('.').length === 3,
      'jwtFromClient looks like a jwt',
    );

    assert.equal(
      jwtFromClient,
      await client.getJWT(),
      'jwt is the same which means it is cached until it is about to expire',
    );
  });

  test('it refreshes the jwt if it is about to expire in the client', async function (assert) {
    let jwtFromClient = createJWT('10s');
    client['jwt'] = jwtFromClient; // Expires very soon, so the client will first refresh it
    assert.notEqual(jwtFromClient, await client.getJWT(), 'jwt got refreshed');
  });

  test('it refreshes the jwt if it expired in the client', async function (assert) {
    let jwtFromClient = createJWT(Date.now() / 1000 - 1); // Expired 1 second ago
    client['jwt'] = jwtFromClient; // Expires very soon, so the client will first refresh it
    assert.notEqual(jwtFromClient, await client.getJWT(), 'jwt got refreshed');
  });
});
