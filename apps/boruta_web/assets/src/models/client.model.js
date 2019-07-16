import axios from 'axios'
import Scope from '@/models/scope.model'

const defaults = {
  authorize_scopes: false,
  authorized_scopes: []
}

const assign = {
  id: function ({ id }) { this.id = id },
  secret: function ({ secret }) { this.secret = secret },
  redirect_uri: function ({ redirect_uri }) { this.redirect_uri = redirect_uri },
  authorize_scope: function ({ authorize_scope }) { this.authorize_scope = authorize_scope },
  authorized_scopes: function ({ authorized_scopes }) {
    this.authorized_scopes = authorized_scopes.map((scope) => {
      return { model: new Scope(scope) }
    })
  }
}
class Client {
  constructor (params = {}) {
    Object.assign(this, defaults)

    Object.keys(params).forEach((key) => {
      this[key] = params[key]
      assign[key].bind(this)(params)
    })
  }

  validate () {
    return new Promise((resolve, reject) => {
      this.authorized_scopes.forEach(({ model: scope }) => {
        if (!scope.persisted) {
          return reject({ authorized_scopes: [ 'cannot be empty' ] })
        }
        if (this.authorized_scopes.filter(({ model: e }) => e.id === scope.id).length > 1) {
          reject({ authorized_scopes: [ 'must be unique' ] })
        }
      })
      resolve()
    })
  }
  save () {
    const { id, serialized } = this
    if (id) {
      return this.constructor.api().patch(`/${id}`, { client: serialized })
        .then(({ data }) => Object.assign(this, data.data))
    } else {
      return this.constructor.api().post('/', { client: serialized })
        .then(({ data }) => Object.assign(this, data.data))
    }
  }

  destroy () {
    return this.constructor.api().delete(`/${this.id}`)
  }

  get serialized () {
    const { id, secret, redirect_uri, authorize_scope, authorized_scopes } = this

    return {
      id,
      secret,
      redirect_uri,
      authorize_scope,
      authorized_scopes: authorized_scopes.map(({ model }) => model.serialized)
    }
  }
}

Client.api = function () {
  const accessToken = localStorage.getItem('vue-authenticate.vueauth_token')

  return axios.create({
    baseURL: `${process.env.VUE_APP_BORUTA_BASE_URL}/api/clients`,
    headers: { 'Authorization': `Bearer ${accessToken}` }
  })
}

Client.all = function () {
  return this.api().get('/').then(({ data }) => {
    return data.data.map((client) => new Client(client))
  })
}

Client.get = function (id) {
  return this.api().get(`/${id}`).then(({ data }) => {
    return new Client(data.data)
  })
}

export default Client